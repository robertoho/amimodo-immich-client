import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/immich_album.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../widgets/photo_grid_item.dart';
import '../widgets/pinch_zoom_grid.dart';
import '../widgets/section_header.dart';
import '../utils/date_utils.dart';

class AlbumDetailScreen extends StatefulWidget {
  final ImmichAlbum album;
  final ImmichApiService apiService;

  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.apiService,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final GridScaleService _gridScaleService = GridScaleService();
  List<ImmichAsset> _assets = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Photo grouping
  bool _groupByMonth =
      true; // Re-enable grouping by default with safe implementation
  List<GroupedGridItem> _groupedItems = [];

  @override
  void initState() {
    super.initState();
    _loadAlbumAssets();
    _gridScaleService.addListener(_onGridScaleChanged);
  }

  @override
  void dispose() {
    _gridScaleService.removeListener(_onGridScaleChanged);
    super.dispose();
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
      setState(() {
        _assets = assets;
        _isLoading = false;

        // Generate grouped items if grouping is enabled
        if (_groupByMonth && assets.isNotEmpty) {
          final groupedAssets = PhotoDateUtils.groupAssetsByMonth(assets);
          _groupedItems = PhotoDateUtils.createGroupedGridItems(groupedAssets);
        } else {
          _groupedItems = [];
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        itemCount: assets.length,
        itemBuilder: (context, index) {
          final asset = assets[index];
          final globalIndex = _assets.indexOf(asset);
          return PhotoGridItem(
            asset: asset,
            apiService: widget.apiService,
            assetList: _assets,
            assetIndex: globalIndex >= 0 ? globalIndex : 0,
          );
        },
      ),
    );
  }

  Widget _buildUngroupedGrid(int columnCount) {
    return SliverMasonryGrid.count(
      crossAxisCount: columnCount,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childCount: _assets.length,
      itemBuilder: (context, index) {
        return PhotoGridItem(
          asset: _assets[index],
          apiService: widget.apiService,
          assetList: _assets,
          assetIndex: index,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.album.albumName),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _refreshAssets,
              tooltip: 'Refresh album',
            ),
            if (_assets.isNotEmpty)
              IconButton(
                icon: Icon(_groupByMonth ? Icons.view_list : Icons.view_module),
                onPressed: _toggleGrouping,
                tooltip:
                    _groupByMonth ? 'Switch to grid view' : 'Group by month',
              ),
          ],
        ),
        body: _buildBody(),
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
          padding: const EdgeInsets.all(16.0),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columnCount = _getGridColumnCount(constraints.maxWidth);
                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(16.0),
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
      ],
    );
  }
}
