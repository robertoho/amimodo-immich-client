import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../widgets/photo_grid_item.dart';
import '../widgets/pinch_zoom_grid.dart';

class PhotosGrid extends StatefulWidget {
  final ImmichApiService apiService;

  const PhotosGrid({super.key, required this.apiService});

  @override
  State<PhotosGrid> createState() => _PhotosGridState();
}

class _PhotosGridState extends State<PhotosGrid> {
  final GridScaleService _gridScaleService = GridScaleService();
  List<ImmichAsset> _assets = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentPage = 1;
  bool _hasMoreData = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _gridScaleService.addListener(_onGridScaleChanged);
    _loadPhotos();
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
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      if (!_isLoading && _hasMoreData) {
        _loadMorePhotos();
      }
    }
  }

  Future<void> _loadPhotos() async {
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
      _assets.clear();
      _currentPage = 1;
    });

    try {
      final searchResult = await widget.apiService.searchAssets(
        page: 1,
        size: 100,
        order: 'desc',
      );

      List<dynamic> jsonList;
      if (searchResult['assets'] is List) {
        jsonList = searchResult['assets'] ?? [];
      } else if (searchResult['assets'] is Map) {
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
        _hasMoreData = assets.length == 100;
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

  Future<void> _loadMorePhotos() async {
    if (!widget.apiService.isConfigured || !_hasMoreData) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final searchResult = await widget.apiService.searchAssets(
        page: _currentPage + 1,
        size: 100,
        order: 'desc',
      );

      List<dynamic> jsonList;
      if (searchResult['assets'] is List) {
        jsonList = searchResult['assets'] ?? [];
      } else if (searchResult['assets'] is Map) {
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
        _hasMoreData = assets.length == 100;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading more photos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  int _getGridColumnCount(double width) {
    return _gridScaleService.getGridColumnCount(width);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _assets.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading photos...'),
          ],
        ),
      );
    }

    if (_hasError && _assets.isEmpty) {
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
                onPressed: _loadPhotos,
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
              Icons.photo_library_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No photos found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure your Immich server is running and accessible',
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadPhotos,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPhotos,
      child: PinchZoomGrid(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columnCount = _getGridColumnCount(constraints.maxWidth);
            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16.0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      '${_assets.length} photo${_assets.length == 1 ? '' : 's'}',
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
                    childCount: _assets.length,
                    itemBuilder: (context, index) {
                      return PhotoGridItem(
                        asset: _assets[index],
                        apiService: widget.apiService,
                        assetList: _assets,
                        assetIndex: index,
                      );
                    },
                  ),
                ),
                if (_isLoading)
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
}
