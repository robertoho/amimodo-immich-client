import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../services/virtualized_photo_service.dart';
import '../services/grid_scale_service.dart';
import '../services/immich_api_service.dart';
import '../widgets/photo_grid_item.dart';
import '../widgets/pinch_zoom_grid.dart';

class VirtualizedPhotoGrid extends StatefulWidget {
  final ImmichApiService apiService;

  const VirtualizedPhotoGrid({
    super.key,
    required this.apiService,
  });

  @override
  State<VirtualizedPhotoGrid> createState() => _VirtualizedPhotoGridState();
}

class _VirtualizedPhotoGridState extends State<VirtualizedPhotoGrid> {
  late final VirtualizedPhotoService _photoService;
  final GridScaleService _gridScaleService = GridScaleService();
  final ScrollController _scrollController = ScrollController();
  int _visibleTilesCount = 0;

  @override
  void initState() {
    super.initState();
    _photoService = VirtualizedPhotoService(widget.apiService);
    _photoService.addListener(_onPhotoServiceChanged);
    _gridScaleService.addListener(_onGridScaleChanged);
    _scrollController.addListener(_onScroll);

    // Initialize the service
    _photoService.initialize();
  }

  @override
  void dispose() {
    _photoService.removeListener(_onPhotoServiceChanged);
    _gridScaleService.removeListener(_onGridScaleChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPhotoServiceChanged() {
    if (mounted) {
      setState(() {});
      // Trigger visible range calculation when photos are loaded
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadVisibleRange();
      });
    }
  }

  void _onGridScaleChanged() {
    if (mounted) {
      setState(() {});
      // Trigger visible range calculation after scale change
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadVisibleRange();
      });
    }
  }

  void _onScroll() {
    _loadVisibleRange();
  }

  void _loadVisibleRange() {
    if (!_photoService.isInitialized) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final scrollOffset = _scrollController.offset;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;

    // Calculate grid properties
    final screenWidth = MediaQuery.of(context).size.width;
    final columnCount = _gridScaleService.getGridColumnCount(screenWidth);
    final padding = 4.0 * 2; // Left and right padding
    final spacing = 0.0;
    final availableWidth =
        screenWidth - padding - ((columnCount - 1) * spacing);
    final itemWidth = availableWidth / columnCount;
    final estimatedItemHeight = itemWidth; // Assume square-ish items
    final itemHeightWithSpacing = estimatedItemHeight + spacing;

    // Calculate visible range
    final itemsPerRow = columnCount;
    final visibleStartRow = (scrollOffset / itemHeightWithSpacing).floor();
    final visibleEndRow =
        ((scrollOffset + viewportHeight) / itemHeightWithSpacing).ceil();

    final visibleStartIndex =
        (visibleStartRow * itemsPerRow).clamp(0, _photoService.totalCount - 1);
    final visibleEndIndex = ((visibleEndRow + 1) * itemsPerRow)
        .clamp(0, _photoService.totalCount - 1);

    // Update visible tiles count
    _visibleTilesCount = (visibleEndIndex - visibleStartIndex + 1)
        .clamp(0, _photoService.totalCount);

    // Load visible range plus buffer
    _photoService.loadVisibleRange(visibleStartIndex, visibleEndIndex);

    // Update UI with new counts
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refresh() async {
    await _photoService.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_photoService.isInitialized) {
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

    if (_photoService.lastError != null) {
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
                _photoService.lastError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_photoService.totalCount == 0) {
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
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return PinchZoomGrid(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final columnCount =
                    _gridScaleService.getGridColumnCount(constraints.maxWidth);

                return CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(4.0),
                      sliver: SliverMasonryGrid.count(
                        crossAxisCount: columnCount,
                        mainAxisSpacing: 0,
                        crossAxisSpacing: 0,
                        childCount: _photoService.totalCount,
                        itemBuilder: (context, index) {
                          final asset = _photoService.getAsset(index);

                          if (asset == null) {
                            // Show loading placeholder
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: AspectRatio(
                                aspectRatio: 1.0,
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }

                          return PhotoGridItem(
                            asset: asset,
                            apiService: widget.apiService,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            // Debug info label
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Visible: $_visibleTilesCount | Loaded: ${_photoService.loadedAssetsCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
