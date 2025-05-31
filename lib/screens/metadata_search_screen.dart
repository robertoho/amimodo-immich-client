import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../widgets/photo_grid_item.dart';
import '../widgets/pinch_zoom_grid.dart';

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
    // Trigger pagination when close to bottom (within 200 pixels)
    if (position.pixels >= position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMoreData) {
        print('🔄 Triggering pagination: page ${_currentPage + 1}');
        print(
            '🔄 Current state: loading=$_isLoading, hasMore=$_hasMoreData, assets=${_assets.length}');
        _loadMoreAssets();
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
      final searchResult = await widget.apiService.searchMetadata(
        page: _currentPage + 1,
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
        _assets.addAll(assets);
        _currentPage++;
        _hasMoreData = assets.length == 50;
        _isLoading = false;
      });
      print(
          '🔄 Completed _loadMoreAssets - loaded ${assets.length} assets, hasMore=$_hasMoreData, total=${_assets.length}');
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
        title: const Text('Advanced Search'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showFilterDialog,
            tooltip: 'Search filters',
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
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _assets.isNotEmpty ? _clearFilters : null,
            tooltip: 'Clear results',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showFilterDialog,
        tooltip: 'Advanced Search',
        child: const Icon(Icons.search),
      ),
    );
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
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: SliverMasonryGrid.count(
                      crossAxisCount: columnCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childCount: _assets.length +
                          (_isLoading && _hasMoreData && _assets.isNotEmpty
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        // Debug info for loading tile condition
                        final shouldShowLoadingTile = index == _assets.length &&
                            _isLoading &&
                            _hasMoreData;
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceVariant
                                  .withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withOpacity(0.2),
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
                                      Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withOpacity(0.7),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Loading more...',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
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
                        );
                      },
                    ),
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
}
