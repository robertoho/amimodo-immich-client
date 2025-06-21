import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/immich_album.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../services/background_thumbnail_service.dart';
import '../widgets/photo_grid_item.dart';
import '../widgets/pinch_zoom_grid.dart';
import '../widgets/section_header.dart';
import '../utils/date_utils.dart';
import 'dart:async';

class AlbumDetailScreen extends StatefulWidget {
  final ImmichAlbum album;
  final ImmichApiService apiService;
  final VoidCallback? onOpenSettings;

  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.apiService,
    this.onOpenSettings,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen>
    with WidgetsBindingObserver {
  final GridScaleService _gridScaleService = GridScaleService();
  final BackgroundThumbnailService _backgroundThumbnailService =
      BackgroundThumbnailService();
  final ScrollController _scrollController = ScrollController();

  List<ImmichAsset> _assets = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Photo grouping
  bool _groupByMonth =
      true; // Re-enable grouping by default with safe implementation
  List<GroupedGridItem> _groupedItems = [];

  // Selection mode for removing assets
  bool _isSelectionMode = false;
  Set<String> _selectedAssetIds = {};
  bool _isRemoving = false;

  // Drag selection state
  bool _isDragSelecting = false;
  Offset? _dragStart;
  Set<String> _dragSelectedAssetIds = {};
  Set<String> _originalSelectedAssetIds = {};

  // Grid item positions for drag selection
  final Map<String, GlobalKey> _itemKeys = {};
  final GlobalKey _gridKey = GlobalKey();

  // Path-based selection state
  String? _lastSelectedAssetId;

  // Scroll and thumbnail prioritization
  int _estimatedVisibleStartIndex = 0;
  Timer? _scrollStopTimer;
  static const Duration _scrollStopDelay = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _loadAlbumAssets();
    _gridScaleService.addListener(_onGridScaleChanged);
    _scrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _gridScaleService.removeListener(_onGridScaleChanged);
    _scrollController.dispose();
    _scrollStopTimer?.cancel();
    _backgroundThumbnailService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _backgroundThumbnailService.onAppForeground();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _backgroundThumbnailService.onAppBackground();
        break;
    }
  }

  void _scrollListener() {
    final position = _scrollController.position;

    // Estimate current visible index based on scroll position
    if (_assets.isNotEmpty && position.hasContentDimensions) {
      final maxScrollWithViewport =
          position.maxScrollExtent + position.viewportDimension;
      if (maxScrollWithViewport > 0) {
        final scrollRatio = position.pixels / maxScrollWithViewport;
        final newVisibleIndex =
            (scrollRatio * _assets.length).floor().clamp(0, _assets.length - 1);

        // If visible index has changed significantly, prioritize visible assets
        if ((newVisibleIndex - _estimatedVisibleStartIndex).abs() > 10) {
          _prioritizeVisibleAssets(newVisibleIndex);
        }

        _estimatedVisibleStartIndex = newVisibleIndex;
        _resetScrollStopTimer();
      }
    }
  }

  void _resetScrollStopTimer() {
    _backgroundThumbnailService.notifyAppIsBusy();
    _scrollStopTimer?.cancel();
    _scrollStopTimer = Timer(_scrollStopDelay, _onScrollStopped);
  }

  void _onScrollStopped() {
    _backgroundThumbnailService.notifyAppIsIdle(widget.apiService);
  }

  void _prioritizeVisibleAssets(int visibleIndex) {
    if (_assets.isEmpty) return;

    // Prioritize assets around the visible area
    const int priorityBuffer = 30;
    final startIndex = (visibleIndex - priorityBuffer).clamp(0, _assets.length);
    final endIndex = (visibleIndex + priorityBuffer).clamp(0, _assets.length);

    final visibleAssets = _assets.sublist(startIndex, endIndex);
    final assetIds = visibleAssets.map((asset) => asset.id).toList();

    if (assetIds.isNotEmpty) {
      debugPrint(
          '⚡ Prioritizing ${assetIds.length} album thumbnails around index $visibleIndex');
      _backgroundThumbnailService.prioritizeAssets(assetIds, widget.apiService);
    }
  }

  void _onGridScaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadAlbumAssets() async {
    if (!widget.apiService.isConfigured) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Please configure your Immich server settings';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final assets = await widget.apiService.getAlbumAssets(widget.album.id);
      if (mounted) {
        setState(() {
          _assets = assets;
          _isLoading = false;

          // Generate grouped items if grouping is enabled
          if (_groupByMonth && assets.isNotEmpty) {
            final groupedAssets = PhotoDateUtils.groupAssetsByMonth(assets);
            _groupedItems =
                PhotoDateUtils.createGroupedGridItems(groupedAssets);
          } else {
            _groupedItems = [];
          }
        });

        // Prioritize initial visible thumbnails
        if (assets.isNotEmpty) {
          final initialAssets = assets.take(50).toList(); // First 50 assets
          final assetIds = initialAssets.map((asset) => asset.id).toList();
          debugPrint(
              '🚀 Prioritizing ${assetIds.length} initial album thumbnails');
          _backgroundThumbnailService.prioritizeAssets(
              assetIds, widget.apiService);

          // Also start background download for all album assets
          _backgroundThumbnailService.startBackgroundDownload(
              assets, widget.apiService);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _refreshAssets() async {
    await _loadAlbumAssets();
  }

  void _toggleGrouping() {
    setState(() {
      _groupByMonth = !_groupByMonth;

      if (_groupByMonth && _assets.isNotEmpty) {
        // Generate grouped items
        final groupedAssets = PhotoDateUtils.groupAssetsByMonth(_assets);
        _groupedItems = PhotoDateUtils.createGroupedGridItems(groupedAssets);
      } else {
        // Clear grouped items for ungrouped view
        _groupedItems = [];
      }
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedAssetIds.clear();
        _clearDragSelection();
      }
    });
  }

  void _toggleAssetSelection(String assetId) {
    setState(() {
      if (_selectedAssetIds.contains(assetId)) {
        _selectedAssetIds.remove(assetId);
      } else {
        _selectedAssetIds.add(assetId);
      }
    });
  }

  void _selectAllAssets() {
    setState(() {
      _selectedAssetIds = _assets.map((asset) => asset.id).toSet();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedAssetIds.clear();
      _clearDragSelection();
    });
  }

  void _clearDragSelection() {
    _isDragSelecting = false;
    _dragStart = null;
    _dragSelectedAssetIds.clear();
    _originalSelectedAssetIds.clear();
    _lastSelectedAssetId = null;
  }

  void _startDragSelection(Offset position) {
    if (!_isSelectionMode) return;

    setState(() {
      _isDragSelecting = false; // Don't start immediately
      _dragStart = position;
      _originalSelectedAssetIds = Set.from(_selectedAssetIds);
      _dragSelectedAssetIds.clear();
      _lastSelectedAssetId = null;
    });
  }

  void _updateDragSelection(Offset position) {
    if (_dragStart == null) return;

    // Only start drag selection if the user has moved far enough
    const double minDragDistance = 10.0;
    final distance = (position - _dragStart!).distance;

    if (!_isDragSelecting && distance > minDragDistance) {
      setState(() {
        _isDragSelecting = true;
      });
    }

    if (_isDragSelecting) {
      setState(() {
        _selectAssetAtPosition(position);
      });
    }
  }

  void _selectAssetAtPosition(Offset position) {
    // Find the asset at the current position
    String? assetAtPosition = _getAssetAtPosition(position);

    if (assetAtPosition != null) {
      // If we have a last selected asset and it's different from current,
      // fill the gap between them
      if (_lastSelectedAssetId != null &&
          _lastSelectedAssetId != assetAtPosition) {
        _selectLinearPath(_lastSelectedAssetId!, assetAtPosition);
      }

      // Always select the current asset
      _dragSelectedAssetIds.add(assetAtPosition);
      _lastSelectedAssetId = assetAtPosition;
    }
  }

  String? _getAssetAtPosition(Offset position) {
    // Check each asset to see if the position is within its bounds
    for (final asset in _assets) {
      final itemKey = _itemKeys[asset.id];
      if (itemKey?.currentContext != null) {
        final RenderBox? renderBox =
            itemKey!.currentContext!.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final RenderBox? gridRenderBox =
              _gridKey.currentContext?.findRenderObject() as RenderBox?;
          if (gridRenderBox != null) {
            // Get the position of the item relative to the grid
            final itemPosition =
                renderBox.localToGlobal(Offset.zero, ancestor: gridRenderBox);
            final itemSize = renderBox.size;
            final itemRect = Rect.fromLTWH(
              itemPosition.dx,
              itemPosition.dy,
              itemSize.width,
              itemSize.height,
            );

            // Check if the position is within this item
            if (itemRect.contains(position)) {
              return asset.id;
            }
          }
        }
      }
    }
    return null;
  }

  void _selectLinearPath(String fromAssetId, String toAssetId) {
    // Find the indices of both assets in the current assets list
    int fromIndex = _assets.indexWhere((asset) => asset.id == fromAssetId);
    int toIndex = _assets.indexWhere((asset) => asset.id == toAssetId);

    if (fromIndex == -1 || toIndex == -1) return;

    // Ensure we go from smaller to larger index
    int startIndex = fromIndex < toIndex ? fromIndex : toIndex;
    int endIndex = fromIndex < toIndex ? toIndex : fromIndex;

    // Select all assets between (and including) the start and end indices
    for (int i = startIndex; i <= endIndex; i++) {
      _dragSelectedAssetIds.add(_assets[i].id);
    }
  }

  void _endDragSelection() {
    if (!_isDragSelecting) return;

    setState(() {
      // Finalize the selection
      _selectedAssetIds = Set.from(_originalSelectedAssetIds)
        ..addAll(_dragSelectedAssetIds);
      _clearDragSelection();
    });
  }

  GlobalKey _getItemKey(String assetId) {
    return _itemKeys.putIfAbsent(assetId, () => GlobalKey());
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (_isSelectionMode) {
            _toggleSelectionMode();
            return KeyEventResult.handled;
          } else {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isSelectionMode
              ? Text(
                  '${_selectedAssetIds.length + _dragSelectedAssetIds.length} selected')
              : null,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _toggleSelectionMode,
                  tooltip: 'Exit selection mode',
                )
              : null,
          actions: [
            if (_isSelectionMode) ...[
              // Selection mode actions
              if (_selectedAssetIds.length + _dragSelectedAssetIds.length <
                  _assets.length)
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: _selectAllAssets,
                  tooltip: 'Select all',
                ),
              if (_selectedAssetIds.isNotEmpty ||
                  _dragSelectedAssetIds.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _clearSelection,
                  tooltip: 'Clear selection',
                ),
              if (_selectedAssetIds.isNotEmpty ||
                  _dragSelectedAssetIds.isNotEmpty)
                IconButton(
                  icon: _isRemoving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  onPressed: _isRemoving ? null : _removeSelectedAssets,
                  tooltip: 'Remove from album',
                ),
            ] else ...[
              // Normal mode actions
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : _refreshAssets,
                tooltip: 'Refresh album',
              ),
              if (_assets.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.checklist),
                  onPressed: _toggleSelectionMode,
                  tooltip: 'Select photos',
                ),
              if (_assets.isNotEmpty)
                IconButton(
                  icon:
                      Icon(_groupByMonth ? Icons.view_list : Icons.view_module),
                  onPressed: _toggleGrouping,
                  tooltip:
                      _groupByMonth ? 'Switch to grid view' : 'Group by month',
                ),
              if (widget.onOpenSettings != null)
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: widget.onOpenSettings,
                  tooltip: 'Settings',
                ),
            ],
          ],
        ),
        extendBodyBehindAppBar: true,
        body: _buildBody(),
        bottomNavigationBar: _isSelectionMode &&
                (_selectedAssetIds.isNotEmpty ||
                    _dragSelectedAssetIds.isNotEmpty)
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_selectedAssetIds.length + _dragSelectedAssetIds.length} photo(s) selected',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ),
                      if (_selectedAssetIds.length +
                              _dragSelectedAssetIds.length <
                          _assets.length)
                        TextButton.icon(
                          onPressed: _selectAllAssets,
                          icon: const Icon(Icons.select_all, size: 18),
                          label: const Text('Select All'),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isRemoving ? null : _removeSelectedAssets,
                        icon: _isRemoving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_outline, size: 18),
                        label: Text(_isRemoving ? 'Removing...' : 'Remove'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading album photos...'),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _refreshAssets,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_assets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_album_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Empty Album',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'This album doesn\'t contain any photos yet',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refreshAssets,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Album info header
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            left: 16.0,
            right: 16.0,
            top: 16.0 + MediaQuery.of(context).padding.top + kToolbarHeight,
            bottom: 16.0,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.shade300,
                width: 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.album.albumName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.photo,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_assets.length} ${_assets.length == 1 ? 'photo' : 'photos'}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  if (widget.album.shared) ...[
                    Icon(
                      Icons.people,
                      size: 16,
                      color: Colors.blue.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Shared',
                      style: TextStyle(
                        color: Colors.blue.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (widget.album.hasSharedLink) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.link,
                      size: 16,
                      color: Colors.orange.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Public Link',
                      style: TextStyle(
                        color: Colors.orange.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              if (widget.album.description != null &&
                  widget.album.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  widget.album.description!,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Photos grid
        Expanded(
          child: PinchZoomGrid(
            child: RefreshIndicator(
              onRefresh: _refreshAssets,
              child: _buildDragSelectionWrapper(
                child: LayoutBuilder(
                  key: _gridKey,
                  builder: (context, constraints) {
                    final columnCount =
                        _getGridColumnCount(constraints.maxWidth);
                    return CustomScrollView(
                      controller: _scrollController,
                      physics: _isSelectionMode
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(4.0),
                          sliver: _groupByMonth && _groupedItems.isNotEmpty
                              ? _buildGroupedGrid(columnCount)
                              : _buildUngroupedGrid(columnCount),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  int _getGridColumnCount(double width) {
    return _gridScaleService.getGridColumnCount(width);
  }

  Widget _buildGroupedGrid(int columnCount) {
    if (_groupedItems.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    // Group consecutive assets by month for better rendering
    List<Widget> groupedWidgets = [];
    List<ImmichAsset> currentMonthAssets = [];
    String? currentMonthTitle;

    for (int i = 0; i < _groupedItems.length; i++) {
      final item = _groupedItems[i];

      if (item.type == GroupedGridItemType.header) {
        // Add previous month's assets as a grid if any
        if (currentMonthAssets.isNotEmpty && currentMonthTitle != null) {
          groupedWidgets.add(_buildMonthGrid(currentMonthAssets, columnCount));
        }

        // Add section header
        groupedWidgets.add(SectionHeader(
          title: item.displayText!,
          assetCount: item.assetCount!,
        ));

        // Reset for new month
        currentMonthAssets = [];
        currentMonthTitle = item.displayText;
      } else {
        // Collect assets for current month
        if (item.asset != null) {
          currentMonthAssets.add(item.asset!);
        }
      }
    }

    // Add the last month's assets
    if (currentMonthAssets.isNotEmpty) {
      groupedWidgets.add(_buildMonthGrid(currentMonthAssets, columnCount));
    }

    // Return as a SliverList with proper widgets
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => groupedWidgets[index],
        childCount: groupedWidgets.length,
      ),
    );
  }

  Widget _buildMonthGrid(List<ImmichAsset> assets, int columnCount) {
    // Create a grid layout for photos within a month
    return Container(
      margin: const EdgeInsets.all(0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnCount,
          crossAxisSpacing: 0,
          mainAxisSpacing: 0,
          childAspectRatio: 1.0,
        ),
        itemCount: assets.length,
        itemBuilder: (context, index) {
          final asset = assets[index];
          final globalIndex = _assets.indexOf(asset);
          final isSelected = _selectedAssetIds.contains(asset.id) ||
              _originalSelectedAssetIds.contains(asset.id) ||
              _dragSelectedAssetIds.contains(asset.id);

          return Container(
            key: _getItemKey(asset.id),
            child: PhotoGridItem(
              asset: asset,
              apiService: widget.apiService,
              assetList: _assets,
              assetIndex: globalIndex >= 0 ? globalIndex : 0,
              isSelectionMode: _isSelectionMode,
              isSelected: isSelected,
              onSelectionToggle: () => _toggleAssetSelection(asset.id),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUngroupedGrid(int columnCount) {
    return SliverMasonryGrid.count(
      crossAxisCount: columnCount,
      mainAxisSpacing: 0,
      crossAxisSpacing: 0,
      childCount: _assets.length,
      itemBuilder: (context, index) {
        final asset = _assets[index];
        final isSelected = _selectedAssetIds.contains(asset.id) ||
            _originalSelectedAssetIds.contains(asset.id) ||
            _dragSelectedAssetIds.contains(asset.id);

        return Container(
          key: _getItemKey(asset.id),
          child: PhotoGridItem(
            asset: asset,
            apiService: widget.apiService,
            assetList: _assets,
            assetIndex: index,
            isSelectionMode: _isSelectionMode,
            isSelected: isSelected,
            onSelectionToggle: () => _toggleAssetSelection(asset.id),
          ),
        );
      },
    );
  }

  Widget _buildDragSelectionWrapper({required Widget child}) {
    return GestureDetector(
      onPanStart: _isSelectionMode
          ? (details) {
              _startDragSelection(details.localPosition);
            }
          : null,
      onPanUpdate: _isSelectionMode
          ? (details) {
              _updateDragSelection(details.localPosition);
            }
          : null,
      onPanEnd: _isSelectionMode
          ? (details) {
              _endDragSelection();
            }
          : null,
      child: child,
    );
  }

  Future<void> _removeSelectedAssets() async {
    // Combine regular selected and drag selected assets
    final allSelectedIds = <String>{
      ..._selectedAssetIds,
      ..._dragSelectedAssetIds,
    };

    if (allSelectedIds.isEmpty) return;

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Photos'),
        content: Text(
          'Are you sure you want to remove ${allSelectedIds.length} photo(s) from this album?\n\nNote: This will only remove them from the album, not delete them permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (shouldRemove != true) return;

    setState(() {
      _isRemoving = true;
    });

    try {
      final results = await widget.apiService.removeAssetFromAlbum(
        widget.album.id,
        allSelectedIds.toList(),
      );

      final successful = results.where((r) => r['success'] == true).length;
      final failed = results.length - successful;

      if (mounted) {
        // Show result message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              successful > 0
                  ? failed == 0
                      ? 'Successfully removed $successful photo(s) from album'
                      : 'Removed $successful photo(s), $failed failed'
                  : 'Failed to remove photos from album',
            ),
            backgroundColor: successful > 0
                ? (failed == 0 ? Colors.green : Colors.orange)
                : Colors.red,
          ),
        );

        // Refresh the album to reflect changes
        await _loadAlbumAssets();

        // Exit selection mode
        setState(() {
          _isSelectionMode = false;
          _selectedAssetIds.clear();
          _clearDragSelection();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing photos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRemoving = false;
        });
      }
    }
  }
}
