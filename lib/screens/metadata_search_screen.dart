import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../widgets/photo_grid_item.dart';
import '../widgets/pinch_zoom_grid.dart';
import '../widgets/section_header.dart';
import '../utils/date_utils.dart';

class MetadataSearchScreen extends StatefulWidget {
  final ImmichApiService apiService;

  const MetadataSearchScreen({super.key, required this.apiService});

  @override
  State<MetadataSearchScreen> createState() => _MetadataSearchScreenState();
}

class _MetadataSearchScreenState extends State<MetadataSearchScreen> {
  final GridScaleService _gridScaleService = GridScaleService();
  List<ImmichAsset> _assets = [];
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentPage = 1;
  bool _hasMoreData = true;
  final ScrollController _scrollController = ScrollController();
  bool _hasPerformedInitialSearch = false;
  bool _showStatusWidget = true; // Toggle for showing status widget

  // Memory management constants
  static const int _maxAssetsBeforeView = 300;
  static const int _preloadAssetsAfterView = 300;
  static const int _assetsPerPage = 50;

  // Track current visible area for memory management
  int _estimatedVisibleStartIndex = 0;

  // Selection functionality
  bool _isSelectionMode = false;
  final Set<String> _selectedAssetIds = <String>{};

  // Photo grouping
  bool _groupByMonth =
      true; // Re-enable grouping by default with safe implementation
  List<GroupedGridItem> _groupedItems = [];

  // Search filters
  bool? _isFavorite;
  bool? _isOffline;
  bool? _isTrashed;
  bool? _isArchived;
  bool _withDeleted = false;
  bool _withArchived = false;
  String? _type;
  String? _city;
  String? _country;
  String? _make;
  String? _model;
  String _sortOrder = 'desc';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _gridScaleService.addListener(_onGridScaleChanged);

    // Perform initial search without filters when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performInitialSearch();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _gridScaleService.removeListener(_onGridScaleChanged);
    super.dispose();
  }

  void _onGridScaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _scrollListener() {
    final position = _scrollController.position;

    // Estimate current visible index based on scroll position
    // Add safety checks to prevent division by zero and invalid arguments
    if (_assets.isNotEmpty && position.hasContentDimensions) {
      final maxScrollWithViewport =
          position.maxScrollExtent + position.viewportDimension;
      if (maxScrollWithViewport > 0) {
        final scrollRatio = position.pixels / maxScrollWithViewport;
        _estimatedVisibleStartIndex =
            (scrollRatio * _assets.length).floor().clamp(0, _assets.length - 1);
      } else {
        _estimatedVisibleStartIndex = 0;
      }
    } else {
      _estimatedVisibleStartIndex = 0;
    }

    // Trigger pagination when close to bottom (within 200 pixels)
    if (position.hasContentDimensions &&
        position.pixels >= position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMoreData) {
        print('🔄 Triggering pagination: page ${_currentPage + 1}');
        print(
            '🔄 Current state: loading=$_isLoading, hasMore=$_hasMoreData, assets=${_assets.length}');
        _loadMoreAssets();
      }
    }

    // Trigger memory cleanup periodically (only if we have content)
    if (_assets.isNotEmpty && position.hasContentDimensions) {
      _performMemoryManagement();
    }
  }

  void _performMemoryManagement() {
    // Safety checks to prevent ArgumentError
    if (_assets.isEmpty ||
        _assets.length < _maxAssetsBeforeView + _preloadAssetsAfterView) {
      return;
    }

    // Ensure valid visible index
    _estimatedVisibleStartIndex =
        _estimatedVisibleStartIndex.clamp(0, _assets.length - 1);

    // Calculate the range we want to keep in memory with safety bounds
    final keepStartIndex = (_estimatedVisibleStartIndex - _maxAssetsBeforeView)
        .clamp(0, _assets.length);
    final keepEndIndex = (_estimatedVisibleStartIndex + _preloadAssetsAfterView)
        .clamp(0, _assets.length);

    // Additional safety check to ensure valid range
    if (keepStartIndex >= keepEndIndex ||
        keepStartIndex < 0 ||
        keepEndIndex > _assets.length) {
      print(
          '🧹 Memory cleanup skipped: invalid range $keepStartIndex-$keepEndIndex');
      return;
    }

    // Only cleanup if we can actually save some memory
    if (keepStartIndex > 0 || keepEndIndex < _assets.length) {
      try {
        final assetsToKeep = _assets.sublist(keepStartIndex, keepEndIndex);
        final removedFromStart = keepStartIndex;
        final removedFromEnd = _assets.length - keepEndIndex;

        print(
            '🧹 Memory cleanup: keeping ${assetsToKeep.length} assets (removed $removedFromStart from start, $removedFromEnd from end)');
        print(
            '🧹 Visible index: $_estimatedVisibleStartIndex, Keep range: $keepStartIndex-$keepEndIndex');

        setState(() {
          _assets = assetsToKeep;
          // Adjust the estimated visible index since we removed items from the start
          _estimatedVisibleStartIndex =
              (_estimatedVisibleStartIndex - removedFromStart)
                  .clamp(0, _assets.length - 1);

          // Adjust current page calculation based on what we kept
          // This is approximate since we're dealing with a sliding window
          _currentPage =
              ((keepEndIndex / _assetsPerPage).ceil()).clamp(1, _currentPage);
        });
      } catch (e) {
        print('❌ Error during memory cleanup: $e');
        // Reset to safe state if something goes wrong
        _estimatedVisibleStartIndex = 0;
      }
    }
  }

  Future<void> _searchAssets() async {
    if (!widget.apiService.isConfigured) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Please configure your Immich server settings';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _assets.clear();
      _currentPage = 1;
    });

    try {
      final searchResult = await widget.apiService.searchMetadata(
        page: 1,
        size: 50,
        order: _sortOrder,
        isFavorite: _isFavorite,
        isOffline: _isOffline,
        isTrashed: _isTrashed,
        isArchived: _isArchived,
        withDeleted: _withDeleted,
        withArchived: _withArchived,
        type: _type,
        city: _city,
        country: _country,
        make: _make,
        model: _model,
      );

      print('🔍 Search result structure: ${searchResult.keys}');
      print('🔍 Assets field type: ${searchResult['assets']?.runtimeType}');

      List<dynamic> jsonList;
      if (searchResult['assets'] is List) {
        // Direct list structure
        jsonList = searchResult['assets'] ?? [];
      } else if (searchResult['assets'] is Map) {
        // Nested structure with items
        final assetsMap = searchResult['assets'] as Map<String, dynamic>;
        jsonList = assetsMap['items'] ?? [];
      } else {
        jsonList = [];
      }

      final assets =
          jsonList.map((json) => ImmichAsset.fromJson(json)).toList();

      setState(() {
        _assets = assets;
        _currentPage = 1;
        _hasMoreData = assets.length == 50;
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

  Future<void> _loadMoreAssets() async {
    if (!widget.apiService.isConfigured || !_hasMoreData) return;

    print('🔄 Starting _loadMoreAssets - setting loading to true');
    setState(() {
      _isLoading = true;
    });

    try {
      // Preload 3 pages at once for better performance
      const pagesToPreload = 3;
      final List<Future<Map<String, dynamic>>> pageFutures = [];

      // Create futures for up to 3 pages
      for (int i = 1; i <= pagesToPreload; i++) {
        final pageToLoad = _currentPage + i;
        pageFutures.add(
          widget.apiService.searchMetadata(
            page: pageToLoad,
            size: _assetsPerPage,
            order: _sortOrder,
            isFavorite: _isFavorite,
            isOffline: _isOffline,
            isTrashed: _isTrashed,
            isArchived: _isArchived,
            withDeleted: _withDeleted,
            withArchived: _withArchived,
            type: _type,
            city: _city,
            country: _country,
            make: _make,
            model: _model,
          ),
        );
      }

      // Execute all page loads in parallel
      final List<Map<String, dynamic>> pageResults =
          await Future.wait(pageFutures);

      final List<ImmichAsset> allNewAssets = [];
      int pagesLoaded = 0;

      // Process each page result
      for (int i = 0; i < pageResults.length; i++) {
        final searchResult = pageResults[i];

        List<dynamic> jsonList;
        if (searchResult['assets'] is List) {
          jsonList = searchResult['assets'] ?? [];
        } else if (searchResult['assets'] is Map) {
          final assetsMap = searchResult['assets'] as Map<String, dynamic>;
          jsonList = assetsMap['items'] ?? [];
        } else {
          jsonList = [];
        }

        final pageAssets =
            jsonList.map((json) => ImmichAsset.fromJson(json)).toList();

        // If we get less than expected assets, this might be the last page
        if (pageAssets.length < _assetsPerPage) {
          allNewAssets.addAll(pageAssets);
          pagesLoaded = i + 1;
          break; // Stop loading more pages as we've reached the end
        } else {
          allNewAssets.addAll(pageAssets);
          pagesLoaded = i + 1;
        }
      }

      setState(() {
        _assets.addAll(allNewAssets);
        _currentPage += pagesLoaded;
        // Check if we have more data based on the last page loaded
        _hasMoreData = pagesLoaded == pagesToPreload &&
            allNewAssets.length == (pagesLoaded * _assetsPerPage);
        _isLoading = false;

        // Regenerate grouped items if grouping is enabled
        if (_groupByMonth && _assets.isNotEmpty) {
          final groupedAssets = PhotoDateUtils.groupAssetsByMonth(_assets);
          _groupedItems = PhotoDateUtils.createGroupedGridItems(groupedAssets);
        } else {
          _groupedItems = [];
        }
      });

      print(
          '🔄 Completed _loadMoreAssets - loaded ${allNewAssets.length} assets from $pagesLoaded pages, hasMore=$_hasMoreData, total=${_assets.length}');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('❌ Error in _loadMoreAssets: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading more results: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _isFavorite = null;
      _isOffline = null;
      _isTrashed = null;
      _isArchived = null;
      _withDeleted = false;
      _withArchived = false;
      _type = null;
      _city = null;
      _country = null;
      _make = null;
      _model = null;
      _sortOrder = 'desc';
      _assets.clear();
      _groupedItems.clear();
    });
    // Perform search with cleared filters
    _searchAssets();
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Advanced Search Filters'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sort Order
                    Text('Sort Order',
                        style: Theme.of(context).textTheme.titleSmall),
                    RadioListTile<String>(
                      title: const Text('Newest first'),
                      value: 'desc',
                      groupValue: _sortOrder,
                      onChanged: (value) =>
                          setDialogState(() => _sortOrder = value!),
                    ),
                    RadioListTile<String>(
                      title: const Text('Oldest first'),
                      value: 'asc',
                      groupValue: _sortOrder,
                      onChanged: (value) =>
                          setDialogState(() => _sortOrder = value!),
                    ),
                    const SizedBox(height: 16),

                    // Media Type
                    Text('Media Type',
                        style: Theme.of(context).textTheme.titleSmall),
                    RadioListTile<String?>(
                      title: const Text('All'),
                      value: null,
                      groupValue: _type,
                      onChanged: (value) => setDialogState(() => _type = value),
                    ),
                    RadioListTile<String>(
                      title: const Text('Images'),
                      value: 'IMAGE',
                      groupValue: _type,
                      onChanged: (value) => setDialogState(() => _type = value),
                    ),
                    RadioListTile<String>(
                      title: const Text('Videos'),
                      value: 'VIDEO',
                      groupValue: _type,
                      onChanged: (value) => setDialogState(() => _type = value),
                    ),
                    const SizedBox(height: 16),

                    // Favorites
                    Text('Favorites',
                        style: Theme.of(context).textTheme.titleSmall),
                    RadioListTile<bool?>(
                      title: const Text('All'),
                      value: null,
                      groupValue: _isFavorite,
                      onChanged: (value) =>
                          setDialogState(() => _isFavorite = value),
                    ),
                    RadioListTile<bool>(
                      title: const Text('Favorites only'),
                      value: true,
                      groupValue: _isFavorite,
                      onChanged: (value) =>
                          setDialogState(() => _isFavorite = value),
                    ),
                    const SizedBox(height: 16),

                    // Advanced Options
                    Text('Advanced Options',
                        style: Theme.of(context).textTheme.titleSmall),
                    SwitchListTile(
                      title: const Text('Include offline assets'),
                      subtitle:
                          const Text('Assets that are no longer available'),
                      value: _isOffline == true,
                      onChanged: (value) => setDialogState(
                          () => _isOffline = value ? true : null),
                    ),
                    SwitchListTile(
                      title: const Text('Include trashed assets'),
                      subtitle: const Text('Assets in trash'),
                      value: _isTrashed == true,
                      onChanged: (value) => setDialogState(
                          () => _isTrashed = value ? true : null),
                    ),
                    SwitchListTile(
                      title: const Text('Include archived assets'),
                      subtitle: const Text('Assets that are archived'),
                      value: _isArchived == true,
                      onChanged: (value) => setDialogState(
                          () => _isArchived = value ? true : null),
                    ),
                    SwitchListTile(
                      title: const Text('Include deleted'),
                      subtitle: const Text(
                          'Show deleted assets (requires server support)'),
                      value: _withDeleted,
                      onChanged: (value) =>
                          setDialogState(() => _withDeleted = value),
                    ),
                    SwitchListTile(
                      title: const Text('Include archived in search'),
                      subtitle:
                          const Text('Include archived assets in results'),
                      value: _withArchived,
                      onChanged: (value) =>
                          setDialogState(() => _withArchived = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    _clearFilters();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Clear All'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {});
                    Navigator.of(context).pop();
                    _searchAssets();
                  },
                  child: const Text('Search'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _getGridColumnCount(double width) {
    return _gridScaleService.getGridColumnCount(width);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode
            ? '${_selectedAssetIds.length} selected'
            : 'Advanced Search'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
                tooltip: 'Exit selection',
              )
            : null,
        actions:
            _isSelectionMode ? _buildSelectionActions() : _buildNormalActions(),
      ),
      body: _buildBody(),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton(
              onPressed: _showFilterDialog,
              tooltip: 'Advanced Search',
              child: const Icon(Icons.search),
            ),
    );
  }

  List<Widget> _buildSelectionActions() {
    return [
      if (_selectedAssetIds.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.album),
          onPressed: _showAddToAlbumDialog,
          tooltip: 'Add to album',
        ),
      IconButton(
        icon: const Icon(Icons.select_all),
        onPressed: _selectedAssetIds.length == _assets.length
            ? _clearSelection
            : _selectAll,
        tooltip: _selectedAssetIds.length == _assets.length
            ? 'Clear selection'
            : 'Select all',
      ),
    ];
  }

  List<Widget> _buildNormalActions() {
    return [
      IconButton(
        icon: const Icon(Icons.tune),
        onPressed: _showFilterDialog,
        tooltip: 'Search filters',
      ),
      // Grouping toggle
      if (_assets.isNotEmpty)
        IconButton(
          icon: Icon(_groupByMonth ? Icons.view_list : Icons.view_module),
          onPressed: _toggleGrouping,
          tooltip: _groupByMonth ? 'Switch to grid view' : 'Group by month',
        ),
      // Test button to manually trigger loading
      if (_assets.isNotEmpty && _hasMoreData)
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            print('🧪 Manual test: triggering _loadMoreAssets');
            _loadMoreAssets();
          },
          tooltip: 'Test load more',
        ),
      if (_assets.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.checklist),
          onPressed: _enterSelectionMode,
          tooltip: 'Select photos',
        ),
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: _assets.isNotEmpty ? _clearFilters : null,
        tooltip: 'Clear results',
      ),
      IconButton(
        icon: Icon(_showStatusWidget ? Icons.visibility : Icons.visibility_off),
        onPressed: () {
          setState(() {
            _showStatusWidget = !_showStatusWidget;
          });
        },
        tooltip:
            _showStatusWidget ? 'Hide status widget' : 'Show status widget',
      ),
    ];
  }

  Widget _buildBody() {
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
                'Search Error',
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
                onPressed: _showFilterDialog,
                icon: const Icon(Icons.search),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_assets.isEmpty && !_isLoading) {
      // Show different messages based on whether initial search was performed
      if (!_hasPerformedInitialSearch) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Advanced Metadata Search',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Search for specific assets using advanced filters like offline status, camera make/model, location, and more',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _showFilterDialog,
                icon: const Icon(Icons.tune),
                label: const Text('Set Search Filters'),
              ),
            ],
          ),
        );
      } else {
        // Show "no results" message after search was performed
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'No Results Found',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'No assets match your current search criteria. Try adjusting your filters or search parameters.',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _showFilterDialog,
                    icon: const Icon(Icons.tune),
                    label: const Text('Adjust Filters'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      _clearFilters();
                      _searchAssets();
                    },
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear All'),
                  ),
                ],
              ),
            ],
          ),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: _searchAssets,
      child: PinchZoomGrid(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columnCount = _getGridColumnCount(constraints.maxWidth);
            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                if (_assets.isNotEmpty) ...[
                  SliverPadding(
                    padding: const EdgeInsets.all(16.0),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Found ${_assets.length} asset${_assets.length == 1 ? '' : 's'}${_hasMoreData ? '+' : ''}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  // Sticky status widget showing pagination and memory info
                  if (_showStatusWidget)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _StatusWidgetDelegate(
                        height: _isLoading
                            ? 140.0
                            : 120.0, // Dynamic height based on loading state
                        child: Container(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .shadowColor
                                      .withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: _buildStatusWidget(),
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: _groupByMonth && _groupedItems.isNotEmpty
                        ? _buildGroupedGrid(columnCount)
                        : _buildUngroupedGrid(columnCount),
                  ),
                ],
                if (_isLoading && _assets.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _performInitialSearch() async {
    if (!_hasPerformedInitialSearch) {
      _hasPerformedInitialSearch = true;
      await _searchAssets();
    }
  }

  Widget _buildStatusWidget() {
    // Calculate pagination statistics with memory management
    final totalLoadedAssets = _assets.length;
    final currentPageAssets =
        _assets.isNotEmpty ? _assetsPerPage.clamp(0, totalLoadedAssets) : 0;

    // With memory management, we need to estimate total position
    final estimatedTotalAssets =
        _currentPage * _assetsPerPage; // Conservative estimate
    final assetsBeforeWindow = _estimatedVisibleStartIndex;
    final assetsAfterWindow =
        (totalLoadedAssets - _estimatedVisibleStartIndex - currentPageAssets)
            .clamp(0, totalLoadedAssets);

    // Calculate visible information
    final loadingTileCount =
        (_isLoading && _hasMoreData && _assets.isNotEmpty) ? 1 : 0;
    final totalTilesInMemory = totalLoadedAssets + loadingTileCount;
    final memoryEfficiency = totalLoadedAssets > 0
        ? ((_maxAssetsBeforeView + _preloadAssetsAfterView) /
                totalLoadedAssets *
                100)
            .clamp(0, 100)
        : 100;

    return Container(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Memory status with efficiency indicator
          Row(
            children: [
              Icon(
                Icons.memory,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Memory: $totalTilesInMemory tiles (${memoryEfficiency.toStringAsFixed(0)}% efficient)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Sliding window info
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _buildStatusItem(
                icon: Icons.skip_previous,
                label: 'Window Before',
                value: '$assetsBeforeWindow',
                color: Colors.grey,
              ),
              _buildStatusItem(
                icon: Icons.visibility,
                label: 'In Memory',
                value: '$totalLoadedAssets',
                color: Theme.of(context).colorScheme.primary,
              ),
              _buildStatusItem(
                icon: Icons.skip_next,
                label: 'Window After',
                value: '$assetsAfterWindow',
                color: Colors.grey,
              ),
              _buildStatusItem(
                icon: Icons.pages,
                label: 'Page',
                value: '$_currentPage${_hasMoreData ? '+' : ''}',
                color: Theme.of(context).colorScheme.secondary,
              ),
            ],
          ),

          // Loading indicator with memory info
          if (_isLoading) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Loading pages ${_currentPage + 1}-${_currentPage + 3}... (will cleanup old data)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color.withOpacity(0.8),
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
        ),
      ],
    );
  }

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedAssetIds.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedAssetIds.addAll(_assets.map((asset) => asset.id));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedAssetIds.clear();
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

  Future<void> _showAddToAlbumDialog() async {
    if (_selectedAssetIds.isEmpty) return;

    try {
      // Get available albums (fresh data)
      final albums = await widget.apiService.getAllAlbums();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Add ${_selectedAssetIds.length} photos to album'),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: albums.isEmpty
                  ? const Center(child: Text('No albums available'))
                  : ListView.builder(
                      key: ValueKey(
                          'albums_${albums.length}_${albums.map((a) => a.assetCount).join('_')}'),
                      itemCount: albums.length,
                      itemBuilder: (context, index) {
                        final album = albums[index];
                        return ListTile(
                          leading: const Icon(Icons.photo_album),
                          title: Text(album.albumName),
                          subtitle: Text(
                              '${album.assetCount} photo${album.assetCount == 1 ? '' : 's'}'),
                          onTap: () {
                            Navigator.of(context).pop();
                            _addSelectedAssetsToAlbum(album.id);
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading albums: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addSelectedAssetsToAlbum(String albumId) async {
    if (_selectedAssetIds.isEmpty) return;

    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Adding ${_selectedAssetIds.length} photos to album...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Call the API to add assets to album
      final results = await widget.apiService
          .addAssetsToAlbum(albumId, _selectedAssetIds.toList());

      // Immediately refresh album information to update cache BEFORE showing success
      try {
        await widget.apiService.getAllAlbums();
        print('✅ Album cache refreshed immediately after adding assets');
      } catch (e) {
        print('⚠️ Failed to refresh album cache: $e');
        // Don't throw here as the main operation was successful
      }

      // Analyze results to categorize them
      final successful = results.where((r) => r['success'] == true).length;
      final duplicated = results.where((r) {
        if (r['success'] == true) {
          return false;
        }
        final error = r['error']?.toString().toLowerCase() ?? '';
        return error.contains('duplicate') ||
            error.contains('already') ||
            error.contains('exists') ||
            error.contains('conflict') ||
            error.contains('present') ||
            error.contains('found');
      }).length;
      final failed = results.length - successful - duplicated;

      if (mounted) {
        String message;
        Color backgroundColor;

        if (successful == results.length) {
          // All successful
          message =
              'Successfully added ${successful} photo${successful == 1 ? '' : 's'} to album';
          backgroundColor = Colors.green;
        } else if (successful > 0) {
          // Mixed results
          List<String> parts = [];
          if (successful > 0) {
            parts.add('${successful} added');
          }
          if (duplicated > 0) {
            parts.add('${duplicated} duplicated');
          }
          if (failed > 0) {
            parts.add('${failed} failed');
          }
          message = parts.join(', ');
          backgroundColor = successful > 0 ? Colors.orange : Colors.red;
        } else if (duplicated > 0 && failed == 0) {
          // All duplicated
          message =
              '${duplicated} photo${duplicated == 1 ? '' : 's'} already in album';
          backgroundColor = Colors.blue;
        } else {
          // All failed
          message = 'Failed to add photos to album';
          backgroundColor = Colors.red;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: backgroundColor,
          ),
        );

        // Exit selection mode if at least some succeeded or were duplicates
        if (successful > 0 || duplicated > 0) {
          _exitSelectionMode();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding photos to album: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
            isSelectionMode: _isSelectionMode,
            isSelected: _selectedAssetIds.contains(asset.id),
            onSelectionToggle: () => _toggleAssetSelection(asset.id),
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
      childCount: _assets.length +
          (_isLoading && _hasMoreData && _assets.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        // Debug info for loading tile condition
        final shouldShowLoadingTile =
            index == _assets.length && _isLoading && _hasMoreData;
        if (index >= _assets.length - 2) {
          // Show debug for last few items
          print(
              '🐛 Item $index: shouldShow=$shouldShowLoadingTile, isLoading=$_isLoading, hasMore=$_hasMoreData, assetsLength=${_assets.length}');
        }

        // Show loading tile at the end when pagination is loading
        if (shouldShowLoadingTile) {
          print(
              '🎯 Rendering loading tile at index $index (total assets: ${_assets.length})');
          return Container(
            height: 200,
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary.withOpacity(0.7),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Loading more...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.7),
                      ),
                ),
              ],
            ),
          );
        }

        // Show regular photo grid item
        return PhotoGridItem(
          asset: _assets[index],
          apiService: widget.apiService,
          isSelectionMode: _isSelectionMode,
          isSelected: _selectedAssetIds.contains(_assets[index].id),
          onSelectionToggle: () => _toggleAssetSelection(_assets[index].id),
          assetList: _assets,
          assetIndex: index,
        );
      },
    );
  }
}

class _StatusWidgetDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  const _StatusWidgetDelegate({
    required this.child,
    this.height = 120.0, // Increased to accommodate all content
  });

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true; // Rebuild to show loading state changes
  }
}
