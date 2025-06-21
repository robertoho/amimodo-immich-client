import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/immich_asset.dart';
import '../models/immich_person.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../services/background_thumbnail_service.dart';
import '../widgets/photo_grid_item.dart';
import '../widgets/pinch_zoom_grid.dart';
import '../widgets/section_header.dart';
import '../utils/date_utils.dart';
import 'dart:async';

class MetadataSearchScreen extends StatefulWidget {
  final ImmichApiService apiService;
  final VoidCallback? onOpenSettings;

  MetadataSearchScreen({
    super.key,
    required this.apiService,
    this.onOpenSettings,
  });

  @override
  State<MetadataSearchScreen> createState() => _MetadataSearchScreenState();
}

class _MetadataSearchScreenState extends State<MetadataSearchScreen> {
  final GridScaleService _gridScaleService = GridScaleService();
  final BackgroundThumbnailService _backgroundThumbnailService =
      BackgroundThumbnailService();
  List<ImmichAsset> _assets = [];
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentPage = 1;
  bool _hasMoreData = true;
  final ScrollController _scrollController = ScrollController();
  bool _hasPerformedInitialSearch = false;
  bool _showStatusWidget = true; // Toggle for showing status widget
  final ValueNotifier<int> _selectedCountNotifier = ValueNotifier<int>(0);
  String _currentDateOverlay = '';

  // Memory management constants
  static const int _maxAssetsBeforeView = 800;
  static const int _preloadAssetsAfterView = 800;
  static const int _assetsPerPage = 200;

  // Track current visible area for memory management
  int _estimatedVisibleStartIndex = 0;

  // Preload starting index management
  int _preloadStartIndex = 0; // The index to use for bidirectional preload
  Timer? _scrollStopTimer; // Timer to detect when scrolling has stopped
  static const Duration _scrollStopDelay =
      Duration(seconds: 3); // Wait 3 seconds after scroll stops

  // Track pagination state independent of memory management
  int _totalAssetsLoaded = 0; // Total number of assets loaded from API
  int _assetsRemovedFromStart =
      0; // Track how many assets were removed from start during cleanup

  // Selection functionality
  bool _isSelectionMode = false;
  final Set<String> _selectedAssetIds = <String>{};
  // Drag selection state
  bool _isDragSelecting = false;
  Offset? _dragStart;
  Set<String> _dragSelectedAssetIds = {};
  Set<String> _originalSelectedAssetIds = {};

  // Grid item positions for drag selection
  final List<MapEntry<String, GlobalKey>> _itemKeys = [];
  final GlobalKey _gridKey = GlobalKey();

  // Path-based selection state
  String? _lastSelectedAssetId;

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
  Set<String> _personIds = {};
  String _sortOrder = 'desc';

  // State for people/face search
  List<ImmichPerson> _people = [];
  List<ImmichPerson> _filteredPeople = [];
  Set<String> _selectedPersonIds = {};
  final TextEditingController _faceSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _gridScaleService.addListener(_onGridScaleChanged);

    // Perform initial search without filters when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performInitialSearch();
      _loadPeople();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _gridScaleService.removeListener(_onGridScaleChanged);
    _backgroundThumbnailService.dispose();
    _clearAllItemKeys(); // Clear all GlobalKeys when disposing
    _selectedCountNotifier.dispose();
    _scrollStopTimer?.cancel(); // Cancel scroll stop timer
    _faceSearchController.dispose();

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
        final newVisibleIndex =
            (scrollRatio * _assets.length).floor().clamp(0, _assets.length - 1);

        // If visible index has changed, prioritize visible assets for download
        // Reduced threshold for more frequent preloading
        if ((newVisibleIndex - _estimatedVisibleStartIndex).abs() > 5) {
          _prioritizeVisibleAssets(newVisibleIndex);
        }

        _estimatedVisibleStartIndex = newVisibleIndex;

        // Update date overlay
        _updateDateOverlay();

        // Reset scroll stop timer - user is still scrolling
        _resetScrollStopTimer();
      } else {
        _estimatedVisibleStartIndex = 0;
      }
    } else {
      _estimatedVisibleStartIndex = 0;
    }

    // Trigger reverse pagination when scrolling very close to the top (within 50 pixels from start)
    // Only restore assets if we have removed assets AND user is actively scrolling up
    // Make this more conservative to prevent sudden jumps
    if (position.hasContentDimensions && position.pixels <= 50) {
      if (!_isLoading && _assetsRemovedFromStart > 0) {
        // Only trigger if we're really at the very top and have removed assets
        print('🔄 Triggering reverse pagination: restoring assets from start');
        print(
            '🔄 Current state: loading=$_isLoading, assetsRemovedFromStart=$_assetsRemovedFromStart, assetsInMemory=${_assets.length}');
        _loadPreviousAssets();
      }
    }

    // Trigger pagination when close to bottom (within 200 pixels)
    // Pagination is independent of memory management - it's based on scroll position
    // and tracks total pages loaded from API (_currentPage) vs assets in memory (_assets.length)
    if (position.hasContentDimensions &&
        position.pixels >= position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMoreData) {
        print('🔄 Triggering pagination: page ${_currentPage + 1}');
        print(
            '🔄 Current state: loading=$_isLoading, hasMore=$_hasMoreData, assetsInMemory=${_assets.length}, totalLoaded=$_totalAssetsLoaded');
        _loadMoreAssets();
      }
    }

    // Trigger memory cleanup periodically (only if we have content)
    if (_assets.isNotEmpty && position.hasContentDimensions) {
      _performMemoryManagement();
    }
  }

  /// Reset the scroll stop timer - called when user is actively scrolling
  void _resetScrollStopTimer() {
    _scrollStopTimer?.cancel();
    _scrollStopTimer = Timer(_scrollStopDelay, _onScrollStopped);
  }

  /// Called when scrolling has stopped for the specified delay
  void _onScrollStopped() {
    // Calculate the global preload starting index based on current position
    final globalStartIndex =
        _assetsRemovedFromStart + _estimatedVisibleStartIndex;

    // Only update if the position has changed significantly (more than 50 assets)
    if ((globalStartIndex - _preloadStartIndex).abs() > 50) {
      _preloadStartIndex = globalStartIndex;

      debugPrint(
          '🎯 Updated preload starting index to $globalStartIndex (visible: $_estimatedVisibleStartIndex, removed: $_assetsRemovedFromStart)');

      // Update the status to reflect new starting position
      if (mounted) {
        setState(() {
          // Force a rebuild to show updated position in status
        });
      }
    }
  }

  void _updateDateOverlay() {
    if (_assets.isNotEmpty &&
        _estimatedVisibleStartIndex >= 0 &&
        _estimatedVisibleStartIndex < _assets.length) {
      final asset = _assets[_estimatedVisibleStartIndex];
      final monthKey =
          '${asset.createdAt.year}-${asset.createdAt.month.toString().padLeft(2, '0')}';
      final formattedDate = PhotoDateUtils.formatMonthHeader(monthKey);

      if (formattedDate != _currentDateOverlay) {
        setState(() {
          _currentDateOverlay = formattedDate;
        });
      }
    }
  }

  void _prioritizeVisibleAssets(int visibleIndex) {
    if (_assets.isEmpty) return;

    // Preload 200 assets before and after current visible index
    const int preloadBuffer = 200;

    // Calculate visible range (current view + some immediate buffer for smooth scrolling)
    final columnCount = _getGridColumnCount(MediaQuery.of(context).size.width);
    final visibleRows = 10; // Approximate visible rows
    final immediateBufferRows = 5; // Extra rows for immediate priority

    // Immediate priority range (for smooth scrolling)
    final immediateStartIndex =
        (visibleIndex - (immediateBufferRows * columnCount))
            .clamp(0, _assets.length);
    final immediateEndIndex =
        (visibleIndex + ((visibleRows + immediateBufferRows) * columnCount))
            .clamp(0, _assets.length);

    // Extended preload range (200 assets before and after)
    final preloadStartIndex =
        (visibleIndex - preloadBuffer).clamp(0, _assets.length);
    final preloadEndIndex =
        (visibleIndex + preloadBuffer).clamp(0, _assets.length);

    // Get immediate priority assets (for current viewport)
    final immediateAssets =
        _assets.sublist(immediateStartIndex, immediateEndIndex);
    final immediateAssetIds = immediateAssets.map((asset) => asset.id).toList();

    // Get extended preload assets
    final preloadAssets = _assets.sublist(preloadStartIndex, preloadEndIndex);
    final preloadAssetIds = preloadAssets.map((asset) => asset.id).toList();

    if (immediateAssetIds.isNotEmpty) {
      print(
          '⚡ Prioritizing ${immediateAssetIds.length} immediate assets for download (index $immediateStartIndex-$immediateEndIndex)');
      _backgroundThumbnailService.prioritizeAssets(
          immediateAssetIds, widget.apiService);
    }

    if (preloadAssetIds.isNotEmpty) {
      print(
          '📥 Preloading ${preloadAssetIds.length} thumbnails for range $preloadStartIndex-$preloadEndIndex (±$preloadBuffer from index $visibleIndex)');
      // Start background download for the extended range
      _backgroundThumbnailService.startBackgroundDownload(
          preloadAssets, widget.apiService);
    }
  }

  void _performMemoryManagement() {
    // MEMORY MANAGEMENT: This method only manages which assets are kept in memory
    // It does NOT affect pagination logic - _currentPage tracks API pages loaded
    // _totalAssetsLoaded tracks total assets loaded from API
    // _assetsRemovedFromStart tracks assets removed from start during cleanup

    // Safety checks to prevent ArgumentError
    if (_assets.isEmpty ||
        _assets.length < _maxAssetsBeforeView + _preloadAssetsAfterView) {
      return;
    }

    // Clean up invalid contexts first
    _cleanupInvalidContextKeys();

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
        // Get asset IDs that will be removed so we can clean up their GlobalKeys
        final assetsToRemove = <String>{};
        if (keepStartIndex > 0) {
          assetsToRemove.addAll(_assets.take(keepStartIndex).map((a) => a.id));
        }
        if (keepEndIndex < _assets.length) {
          assetsToRemove.addAll(_assets.skip(keepEndIndex).map((a) => a.id));
        }

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

          // Track assets removed from start for pagination calculations
          _assetsRemovedFromStart += removedFromStart;

          // Aggressively clean up GlobalKeys for removed assets
          for (final assetId in assetsToRemove) {
            _itemKeys.removeWhere((entry) => entry.key == assetId);
          }

          // Also ensure we only keep keys for assets that still exist
          final currentAssetIds = _assets.map((asset) => asset.id).toSet();
          _itemKeys
              .removeWhere((entry) => !currentAssetIds.contains(entry.key));
        });
      } catch (e) {
        print('❌ Error during memory cleanup: $e');
        // Reset to safe state if something goes wrong
        _estimatedVisibleStartIndex = 0;
        // Clear all GlobalKeys on error to prevent conflicts
        _itemKeys.clear();
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
      _itemKeys.clear(); // Clear GlobalKeys when clearing assets
      _currentPage = 1;
      _totalAssetsLoaded = 0; // Reset total loaded count
      _assetsRemovedFromStart = 0; // Reset removed count
    });

    try {
      final searchResult = await widget.apiService.searchMetadata(
        page: 1,
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
        personIds: _personIds.toList(),
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
        _totalAssetsLoaded = assets.length; // Track total assets loaded
        _hasMoreData = assets.length == _assetsPerPage;
        _isLoading = false;

        // Cleanup old GlobalKeys after setting new assets
        _cleanupRemovedAssetKeys();

        // Initialize preload starting index to the beginning for new searches
        _preloadStartIndex = 0;
        _estimatedVisibleStartIndex = 0;
      });

      // Start background thumbnail downloads for all assets
      if (assets.isNotEmpty) {
        print(
            '🚀 Starting background thumbnail downloads for ${assets.length} assets');
        _backgroundThumbnailService.startBackgroundDownload(
            assets, widget.apiService);

        // Also start initial preloading from the beginning of the list
        print('📥 Starting initial preloading from index 0');
        _prioritizeVisibleAssets(0);
      }
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
            personIds: _personIds.toList(),
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
        _totalAssetsLoaded +=
            allNewAssets.length; // Track total assets loaded from API
        // Check if we have more data based on the last page loaded
        _hasMoreData = pagesLoaded == pagesToPreload &&
            allNewAssets.length == (pagesLoaded * _assetsPerPage);
        _isLoading = false;

        // Cleanup old GlobalKeys after adding new assets
        _cleanupRemovedAssetKeys();
      });

      // Start background thumbnail downloads for new assets
      if (allNewAssets.isNotEmpty) {
        print(
            '🚀 Starting background thumbnail downloads for ${allNewAssets.length} new assets');
        _backgroundThumbnailService.startBackgroundDownload(
            allNewAssets, widget.apiService);

        // Also trigger preloading around the area where new assets were added
        final newAssetsStartIndex = _assets.length - allNewAssets.length;
        print(
            '📥 Starting preloading around newly loaded assets at index $newAssetsStartIndex');
        _prioritizeVisibleAssets(newAssetsStartIndex);
      }

      print(
          '🔄 Completed _loadMoreAssets - loaded ${allNewAssets.length} assets from $pagesLoaded pages, hasMore=$_hasMoreData, totalLoaded=$_totalAssetsLoaded');
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

  Future<void> _loadPreviousAssets() async {
    if (!widget.apiService.isConfigured || _assetsRemovedFromStart <= 0) return;

    print('🔄 Starting _loadPreviousAssets - restoring removed assets');
    setState(() {
      _isLoading = true;
    });

    try {
      // Calculate how many assets to restore (restore in smaller chunks to avoid sudden jumps)
      final assetsToRestore = (_assetsRemovedFromStart)
          .clamp(0, _assetsPerPage); // Only restore one page at a time

      // Calculate which page to load based on the current memory window
      // We need to determine what page contains the assets that were removed from start
      final totalAssetsBeforeMemoryWindow = _assetsRemovedFromStart;

      // Calculate which page contains the assets we need to restore
      // The page number is based on how many assets were removed from start
      final pageToLoad = ((totalAssetsBeforeMemoryWindow - assetsToRestore) ~/
              _assetsPerPage) +
          1;
      final pageToLoadClamped = pageToLoad.clamp(1, _currentPage);

      print(
          '🔄 Restoring $assetsToRestore assets from page $pageToLoadClamped (calculated from ${totalAssetsBeforeMemoryWindow} assets removed from start)');
      print(
          '🔄 Current page: $_currentPage, Total loaded: $_totalAssetsLoaded');

      final searchResult = await widget.apiService.searchMetadata(
        page:
            pageToLoadClamped, // Load the calculated page instead of always page 1
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
        personIds: _personIds.toList(),
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

      final restoredAssets =
          jsonList.map((json) => ImmichAsset.fromJson(json)).toList();

      // Only take the assets that were actually removed (don't duplicate existing assets)
      final currentAssetIds = _assets.map((asset) => asset.id).toSet();
      final assetsToAdd = restoredAssets
          .where((asset) => !currentAssetIds.contains(asset.id))
          .take(assetsToRestore)
          .toList();

      if (assetsToAdd.isNotEmpty) {
        // Store current scroll position more accurately
        final currentScrollPosition =
            _scrollController.position.pixels.toDouble();
        final currentScrollExtent = _scrollController.position.maxScrollExtent;

        setState(() {
          // Add restored assets to the beginning of the list
          _assets.insertAll(0, assetsToAdd);

          // Update tracking variables
          _assetsRemovedFromStart =
              (_assetsRemovedFromStart - assetsToAdd.length)
                  .clamp(0, _totalAssetsLoaded);

          // Adjust visible index since we added items to the start
          _estimatedVisibleStartIndex =
              (_estimatedVisibleStartIndex + assetsToAdd.length)
                  .clamp(0, _assets.length - 1);

          // Update current page to reflect we're now viewing assets from earlier pages
          // Calculate the effective current page based on the assets currently in memory
          final effectiveStartPage = ((_totalAssetsLoaded -
                      _assets.length -
                      _assetsRemovedFromStart) ~/
                  _assetsPerPage) +
              1;
          _currentPage = effectiveStartPage.clamp(1, _currentPage);

          _isLoading = false;

          // Cleanup old GlobalKeys after adding assets
          _cleanupRemovedAssetKeys();
        });

        // Improved scroll position adjustment to prevent sudden jumps
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients &&
              _scrollController.position.hasContentDimensions) {
            // Calculate the estimated height per item based on current grid
            final columnCount =
                _getGridColumnCount(MediaQuery.of(context).size.width);
            final itemsPerRow = columnCount;
            final addedRows = (assetsToAdd.length / itemsPerRow).ceil();

            // Estimate item height (assuming square items with current grid scale)
            final screenWidth = MediaQuery.of(context).size.width;
            final itemWidth =
                (screenWidth - 32) / columnCount; // 32 for padding
            final estimatedItemHeight = itemWidth; // Square items
            final estimatedAddedHeight =
                (addedRows * estimatedItemHeight).toDouble();

            // More conservative scroll adjustment
            final newScrollPosition =
                (currentScrollPosition + estimatedAddedHeight * 0.8)
                    .clamp(0.0, _scrollController.position.maxScrollExtent);

            // Use animateTo instead of jumpTo for smoother transition
            _scrollController.animateTo(
              newScrollPosition,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );

            print(
                '🔄 Smoothly adjusted scroll position: $currentScrollPosition -> $newScrollPosition (added ${assetsToAdd.length} assets, estimated height: $estimatedAddedHeight)');
          }
        });

        // Start background thumbnail downloads for restored assets
        print(
            '🚀 Starting background thumbnail downloads for ${assetsToAdd.length} restored assets');
        _backgroundThumbnailService.startBackgroundDownload(
            assetsToAdd, widget.apiService);

        print(
            '🔄 Completed _loadPreviousAssets - restored ${assetsToAdd.length} assets from page $pageToLoadClamped, assetsRemovedFromStart now: $_assetsRemovedFromStart, updated currentPage to $_currentPage');
      } else {
        setState(() {
          _isLoading = false;
        });
        print('🔄 No new assets to restore from page $pageToLoadClamped');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('❌ Error in _loadPreviousAssets: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading previous results: $e'),
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
      _personIds.clear();
      _selectedPersonIds.clear();
      _assets.clear();
      _itemKeys.clear(); // Clear GlobalKeys when clearing assets
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
              content: SizedBox(
                width: MediaQuery.of(context).size.width,
                child: SingleChildScrollView(
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

                      // Face/People Search
                      if (_people.isNotEmpty) ...[
                        Text('Filter by Person',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        // Search box for faces
                        TextFormField(
                          controller: _faceSearchController,
                          onChanged: (value) {
                            setDialogState(() {
                              _filteredPeople = _people
                                  .where((person) => person.name
                                      .toLowerCase()
                                      .contains(value.toLowerCase()))
                                  .toList();
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search for a person...',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            suffixIcon: _faceSearchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setDialogState(() {
                                        _faceSearchController.clear();
                                        _filteredPeople = _people;
                                      });
                                    },
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // List of faces
                        SizedBox(
                          height: 300,
                          child: GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 6,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                              childAspectRatio: 1.0,
                            ),
                            itemCount: _filteredPeople.length + 1,
                            itemBuilder: (context, index) {
                              // "Any Person" Tile
                              if (index == 0) {
                                final isSelected = _selectedPersonIds.isEmpty;
                                return GestureDetector(
                                  onTap: () => setDialogState(
                                      () => _selectedPersonIds.clear()),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.people,
                                            color: Colors.grey.shade700),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Any',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade800,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              // Person Tile
                              final person = _filteredPeople[index - 1];
                              final isSelected =
                                  _selectedPersonIds.contains(person.id);
                              final thumbnailUrl = widget.apiService
                                  .getPersonThumbnailUrl(person.id);

                              return GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    if (isSelected) {
                                      _selectedPersonIds.remove(person.id);
                                    } else {
                                      _selectedPersonIds.add(person.id);
                                    }
                                  });
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: GridTile(
                                    footer: GridTileBar(
                                      backgroundColor: Colors.black45,
                                      title: Text(
                                        person.name,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: isSelected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(8.0),
                                      ),
                                      child: Image.network(
                                        thumbnailUrl,
                                        headers: widget.apiService.authHeaders,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, obj, trace) =>
                                            const Icon(Icons.face),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Media Type
                      Text('Media Type',
                          style: Theme.of(context).textTheme.titleSmall),
                      RadioListTile<String?>(
                        title: const Text('All'),
                        value: null,
                        groupValue: _type,
                        onChanged: (value) =>
                            setDialogState(() => _type = value),
                      ),
                      RadioListTile<String>(
                        title: const Text('Images'),
                        value: 'IMAGE',
                        groupValue: _type,
                        onChanged: (value) =>
                            setDialogState(() => _type = value),
                      ),
                      RadioListTile<String>(
                        title: const Text('Videos'),
                        value: 'VIDEO',
                        groupValue: _type,
                        onChanged: (value) =>
                            setDialogState(() => _type = value),
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
                    setState(() {
                      // Apply the selected person filter
                      _personIds = Set.from(_selectedPersonIds);
                    });
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
        title: _isSelectionMode
            ? ValueListenableBuilder<int>(
                valueListenable: _selectedCountNotifier,
                builder: (context, selectedCount, _) {
                  return Text('$selectedCount selected');
                },
              )
            : null,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
                tooltip: 'Exit selection',
              )
            : null,
        actions: _isSelectionMode
            ? [
                ValueListenableBuilder<int>(
                  valueListenable: _selectedCountNotifier,
                  builder: (context, selectedCount, _) {
                    return Row(
                      // NOTA: aquí usamos Row para agrupar todos los IconButton
                      // que antes devolvía _buildSelectionActions()
                      children: [
                        // 1) Icono de "Add to album"
                        IconButton(
                          icon: const Icon(Icons.album),
                          onPressed: selectedCount > 0
                              ? _showAddToAlbumDialog
                              : null, // deshabilitado si no hay nada seleccionado
                          tooltip: 'Add to album',
                        ),

                        // 2) Icono de "Select all" / "Clear selection"
                        IconButton(
                          icon: const Icon(Icons.select_all),
                          onPressed: selectedCount == _assets.length
                              ? _clearSelection
                              : _selectAll,
                          tooltip: selectedCount == _assets.length
                              ? 'Clear selection'
                              : 'Select all',
                        ),

                        // …si quieres añadir más acciones en modo selección, agrégalas aquí…
                      ],
                    );
                  },
                )
              ]
            : _buildNormalActions(),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          _buildBody(),
          if (_assets.isNotEmpty && _currentDateOverlay.isNotEmpty)
            Positioned(
              top: 100, // Adjust as needed
              right: 16,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _currentDateOverlay,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
    final totalSelected =
        _selectedAssetIds.length + _dragSelectedAssetIds.length;
    return [
      if (totalSelected > 0)
        IconButton(
          icon: const Icon(Icons.album),
          onPressed: _showAddToAlbumDialog,
          tooltip: 'Add to album',
        ),
      IconButton(
        icon: const Icon(Icons.select_all),
        onPressed:
            totalSelected == _assets.length ? _clearSelection : _selectAll,
        tooltip:
            totalSelected == _assets.length ? 'Clear selection' : 'Select all',
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
      // Background download controls
      if (_assets.isNotEmpty)
        StreamBuilder<BackgroundDownloadStatus>(
          stream: _backgroundThumbnailService.statusStream,
          builder: (context, snapshot) {
            final status =
                snapshot.data ?? _backgroundThumbnailService.currentStatus;
            if (status.total > 0 || status.isFullPreloadRunning) {
              return IconButton(
                icon: Icon(
                  status.isRunning
                      ? Icons.pause
                      : status.isPaused
                          ? Icons.play_arrow
                          : Icons.download_done,
                ),
                onPressed: () {
                  if (status.isRunning) {
                    _backgroundThumbnailService.pauseBackgroundDownload();
                  } else if (status.isPaused) {
                    _backgroundThumbnailService
                        .resumeBackgroundDownload(widget.apiService);
                  }
                },
                tooltip: status.isRunning
                    ? 'Pause downloads'
                    : status.isPaused
                        ? 'Resume downloads'
                        : 'Downloads complete',
              );
            }
            return const SizedBox.shrink();
          },
        ),
      // Full preload button
      if (_assets.isNotEmpty)
        StreamBuilder<BackgroundDownloadStatus>(
          stream: _backgroundThumbnailService.statusStream,
          builder: (context, snapshot) {
            final status =
                snapshot.data ?? _backgroundThumbnailService.currentStatus;
            return IconButton(
              icon: Icon(
                status.isFullPreloadRunning
                    ? Icons.cloud_download
                    : Icons.cloud_sync,
                color: status.isFullPreloadRunning ? Colors.orange : null,
              ),
              onPressed: status.isFullPreloadRunning
                  ? () {
                      _backgroundThumbnailService.stopFullPreload();
                    }
                  : () {
                      _startFullPreload();
                    },
              tooltip: status.isFullPreloadRunning
                  ? 'Stop full preload'
                  : 'Preload all thumbnails',
            );
          },
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
      // Test button to manually trigger reverse loading
      if (_assets.isNotEmpty && _assetsRemovedFromStart > 0)
        IconButton(
          icon: const Icon(Icons.refresh_outlined),
          onPressed: () {
            print('🧪 Manual test: triggering _loadPreviousAssets');
            _loadPreviousAssets();
          },
          tooltip: 'Test load previous',
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
      if (widget.onOpenSettings != null)
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: widget.onOpenSettings,
          tooltip: 'Settings',
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
        child: _isSelectionMode
            ? _buildDragSelectionWrapper(
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
                        if (_assets.isNotEmpty) ...[
                          SliverPadding(
                            padding: EdgeInsets.only(
                              left: 16.0,
                              right: 16.0,
                              top: 16.0 +
                                  MediaQuery.of(context).padding.top +
                                  kToolbarHeight,
                              bottom: 0,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: Text(
                                'Found $_totalAssetsLoaded asset${_totalAssetsLoaded == 1 ? '' : 's'}${_hasMoreData ? '+' : ''}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                          // Sticky status widget showing pagination and memory info
                          if (_showStatusWidget)
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _StatusWidgetDelegate(
                                height:
                                    160.0, // Increased height to accommodate full preload status
                                child: Container(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 16.0, vertical: 8.0),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.surface,
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
                            padding: const EdgeInsets.all(0),
                            sliver: _buildUngroupedGrid(columnCount),
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
              )
            : LayoutBuilder(
                key: _gridKey,
                builder: (context, constraints) {
                  final columnCount = _getGridColumnCount(constraints.maxWidth);
                  return CustomScrollView(
                    controller: _scrollController,
                    physics: _isSelectionMode
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    slivers: [
                      if (_assets.isNotEmpty) ...[
                        SliverPadding(
                          padding: EdgeInsets.only(
                            left: 16.0,
                            right: 16.0,
                            top: 16.0 +
                                MediaQuery.of(context).padding.top +
                                kToolbarHeight,
                            bottom: 0,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              'Found $_totalAssetsLoaded asset${_totalAssetsLoaded == 1 ? '' : 's'}${_hasMoreData ? '+' : ''}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                        // Sticky status widget showing pagination and memory info
                        if (_showStatusWidget)
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _StatusWidgetDelegate(
                              height:
                                  160.0, // Increased height to accommodate full preload status
                              child: Container(
                                color:
                                    Theme.of(context).scaffoldBackgroundColor,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 16.0, vertical: 8.0),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.surface,
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
                          padding: const EdgeInsets.all(0),
                          sliver: _buildUngroupedGrid(columnCount),
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

      // Initialize preload starting index to 0 for initial search
      _preloadStartIndex = 0;

      await _searchAssets();
    }
  }

  /// Start full preload of all thumbnails with current search filters
  Future<void> _startFullPreload() async {
    if (!widget.apiService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure your Immich server settings first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Use the current preload starting index (updated based on scroll position)
    final startingIndex = _preloadStartIndex;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Start Full Preload'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will download thumbnails for ALL assets matching your current search filters, starting from your current position and expanding outward.',
              ),
              const SizedBox(height: 16),
              Text(
                'Starting from position ${startingIndex + 1} of ${_totalAssetsLoaded} total assets.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Currently viewing position ${_estimatedVisibleStartIndex + 1} of ${_assets.length} visible assets.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'This process may take a while and use significant bandwidth and storage.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'Current filters:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              if (_isFavorite != null)
                Text(
                    '• Favorites: ${_isFavorite! ? "Only favorites" : "Non-favorites"}'),
              if (_type != null) Text('• Type: $_type'),
              if (_city != null) Text('• City: $_city'),
              if (_country != null) Text('• Country: $_country'),
              if (_make != null) Text('• Camera make: $_make'),
              if (_model != null) Text('• Camera model: $_model'),
              if (_isOffline == true) const Text('• Including offline assets'),
              if (_isTrashed == true) const Text('• Including trashed assets'),
              if (_isArchived == true)
                const Text('• Including archived assets'),
              Text('• Sort order: $_sortOrder'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Start Preload'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      debugPrint(
          '🎯 Starting preload from global index $startingIndex (visible: $_estimatedVisibleStartIndex, removed: $_assetsRemovedFromStart)');

      // Start the full preload with current search filters and position
      await _backgroundThumbnailService.startFullPreload(
        widget.apiService,
        startIndex: startingIndex,
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
        sortOrder: _sortOrder,
        personIds: _personIds.toList(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Full thumbnail preload started from position ${startingIndex + 1}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Widget _buildStatusWidget() {
    // Calculate pagination statistics with memory management
    final totalLoadedAssets = _assets.length;
    final currentPageAssets =
        _assets.isNotEmpty ? _assetsPerPage.clamp(0, totalLoadedAssets) : 0;

    // Use proper total assets loaded tracking instead of estimation
    final assetsBeforeWindow =
        _assetsRemovedFromStart; // Assets removed from start during cleanup
    final assetsAfterWindow =
        (_totalAssetsLoaded - _assetsRemovedFromStart - totalLoadedAssets)
            .clamp(0, _totalAssetsLoaded);

    // Calculate visible information
    final loadingTileCount =
        (_isLoading && _hasMoreData && _assets.isNotEmpty) ? 1 : 0;
    final totalTilesInMemory = totalLoadedAssets + loadingTileCount;
    final memoryEfficiency = _totalAssetsLoaded > 0
        ? ((_maxAssetsBeforeView + _preloadAssetsAfterView) /
                _totalAssetsLoaded *
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

          // Background download status
          StreamBuilder<BackgroundDownloadStatus>(
            stream: _backgroundThumbnailService.statusStream,
            builder: (context, snapshot) {
              final status =
                  snapshot.data ?? _backgroundThumbnailService.currentStatus;
              if (status.total > 0 || status.isFullPreloadRunning) {
                return Column(
                  children: [
                    // Regular background download status
                    if (status.total > 0) ...[
                      Row(
                        children: [
                          Icon(
                            status.isRunning
                                ? Icons.download
                                : status.isPaused
                                    ? Icons.pause
                                    : Icons.download_done,
                            size: 16,
                            color: status.isRunning
                                ? Colors.green
                                : status.isPaused
                                    ? Colors.orange
                                    : Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Thumbnails: ${status.completed}/${status.total} (${(status.progress * 100).toStringAsFixed(0)}%)',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: status.isRunning
                                          ? Colors.green
                                          : status.isPaused
                                              ? Colors.orange
                                              : Colors.blue,
                                    ),
                          ),
                          if (status.isRunning && status.downloading > 0) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Colors.green),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    // Full preload status
                    if (status.isFullPreloadRunning ||
                        status.totalAssetsDiscovered > 0) ...[
                      Row(
                        children: [
                          Icon(
                            status.isFullPreloadRunning
                                ? Icons.cloud_download
                                : Icons.cloud_done,
                            size: 16,
                            color: status.isFullPreloadRunning
                                ? Colors.orange
                                : Colors.purple,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              status.fullPreloadStatusText,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: status.isFullPreloadRunning
                                        ? Colors.orange
                                        : Colors.purple,
                                  ),
                            ),
                          ),
                          if (status.isFullPreloadRunning &&
                              status.totalAssetsDiscovered > 0) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: status.fullPreloadProgress,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Colors.orange),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),

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
              _buildStatusItem(
                icon: Icons.my_location,
                label: 'Preload Start',
                value: '${_preloadStartIndex + 1}',
                color: Colors.orange,
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
                  _assetsRemovedFromStart > 0
                      ? 'Restoring previous assets...'
                      : 'Loading pages ${_currentPage + 1}-${_currentPage + 3}... (will cleanup old data)',
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
    // Clean up any invalid contexts before entering selection mode
    _cleanupInvalidContextKeys();

    setState(() {
      _isSelectionMode = true;
      // Force clear all GlobalKeys and regenerate them to prevent conflicts
      _itemKeys.clear();
      // Also clear any drag selection state
      _clearDragSelection();
      _selectedCountNotifier.value = 0;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedAssetIds.clear();
      _clearDragSelection();
      // Clear GlobalKeys when exiting selection mode as they're no longer needed
      _itemKeys.clear();
      _selectedCountNotifier.value = 0;
    });
  }

  void _selectAll() {
    setState(() {
      _selectedAssetIds.addAll(_assets.map((asset) => asset.id));
      _selectedCountNotifier.value = _selectedAssetIds.length;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedAssetIds.clear();
      _clearDragSelection();
    });
  }

  void _toggleAssetSelection(String assetId, bool selected) {
    // Don't trigger a full rebuild if we're in drag selection mode
    //  if (_isDragSelecting) {
    //   return;
    //}
    if (_selectedAssetIds.contains(assetId)) {
      _selectedAssetIds.remove(assetId);
    } else {
      _selectedAssetIds.add(assetId);
    }
    _selectedCountNotifier.value = _selectedAssetIds.length;
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

    // setState(() {
    _isDragSelecting = false; // Don't start immediately
    _dragStart = position;
    _originalSelectedAssetIds = Set.from(_selectedAssetIds);
    _dragSelectedAssetIds.clear();
    _lastSelectedAssetId = null;
    //});
  }

  void _updateDragSelection(Offset position) {
    if (_dragStart == null) return;

    // Only start drag selection if the user has moved far enough
    const double minDragDistance = 10.0;
    final distance = (position - _dragStart!).distance;

    if (!_isDragSelecting && distance > minDragDistance) {
      // setState(() {
      _isDragSelecting = true;
      //});
    }

    if (_isDragSelecting) {
      //setState(() {
      _selectAssetAtPosition(position);
      //});
    }
  }

  void _selectAssetAtPosition(Offset position) {
    // Find the asset at the current position
    String? assetAtPosition = _getAssetAtPosition(position);

    if (assetAtPosition != null) {
      // Find the PhotoGridItem widget for this asset and set its isSelected property
      _setAssetSelected(assetAtPosition, true);

      // If we have a last selected asset and it's different from current,
      // fill the gap between them
      if (_lastSelectedAssetId != null &&
          _lastSelectedAssetId != assetAtPosition) {
        _selectLinearPath(_lastSelectedAssetId!, assetAtPosition);
      }

      _lastSelectedAssetId = assetAtPosition;
    }
  }

  void _setAssetSelected(String assetId, bool selected) {
    // Find the PhotoGridItem widget for this asset
    for (final entry in _itemKeys) {
      if (entry.key == assetId && entry.value.currentContext != null) {
        final context = entry.value.currentContext!;

        // Navigate up the widget tree to find the PhotoGridItem
        Widget? widget = context.widget;
        if (widget is PhotoGridItem) {
          widget.setSelected(true);

          // Trigger a rebuild of the widget
          if (context.mounted) {
            //  (context as StatefulElement).markNeedsBuild();
          }
          return;
        }
      }
    }
  }

  String? _getAssetAtPosition(Offset position) {
    // Check each asset to see if the position is within its bounds
    for (final asset in _assets) {
      var matchingEntries =
          _itemKeys.where((entry) => entry.key == asset.id).toList();

      if (matchingEntries.isNotEmpty) {
        // Clean up duplicates if found
        if (matchingEntries.length > 1) {
          print(
              '🔑 Found ${matchingEntries.length} duplicate keys for ${asset.id} in position check, checking contexts...');

          // Filter out entries with invalid contexts
          final validEntries = matchingEntries.where((entry) {
            final context = entry.value.currentContext;
            return context != null && context.mounted;
          }).toList();

          if (validEntries.isNotEmpty) {
            // Keep only the first valid entry
            _itemKeys.removeWhere((entry) => entry.key == asset.id);
            _itemKeys.add(validEntries.first);
            matchingEntries = [validEntries.first];
          }
        }

        final itemKey = matchingEntries.first.value;
        if (itemKey.currentContext != null) {
          final RenderBox? renderBox =
              itemKey.currentContext!.findRenderObject() as RenderBox?;
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
      _setAssetSelected(_assets[i].id, true);
    }
  }

  void _endDragSelection() {
    if (!_isDragSelecting) return;

    // setState(() {
    // Finalize the selection by combining original and drag selected
    //   _selectedAssetIds.clear();
    //   _selectedAssetIds.addAll(_originalSelectedAssetIds);
    //    _selectedAssetIds.addAll(_dragSelectedAssetIds);
    //   _clearDragSelection();
    //});
  }

  GlobalKey _getItemKey(String assetId) {
    // Create new key if none exists
    final key = GlobalKey();
    _itemKeys.add(MapEntry(assetId, key));
    return key;
  }

  void _cleanupInvalidContextKeys() {
    // Remove entries where the GlobalKey's context is no longer valid
    final invalidEntries = <MapEntry<String, GlobalKey>>[];

    for (final entry in _itemKeys) {
      final context = entry.value.currentContext;
      if (context == null || !context.mounted) {
        invalidEntries.add(entry);
      }
    }

    if (invalidEntries.isNotEmpty) {
      print('🔑 Cleaning up ${invalidEntries.length} invalid context keys');
      for (final invalidEntry in invalidEntries) {
        _itemKeys.remove(invalidEntry);
      }
    }
  }

  void _cleanupRemovedAssetKeys() {
    // First clean up invalid contexts
    _cleanupInvalidContextKeys();

    // Get current asset IDs
    final currentAssetIds = _assets.map((asset) => asset.id).toSet();

    // Remove keys for assets that are no longer in the list
    _itemKeys.removeWhere((entry) => !currentAssetIds.contains(entry.key));

    print(
        '🔑 GlobalKey cleanup: ${_itemKeys.length} keys remaining for ${_assets.length} assets');
  }

  void _clearAllItemKeys() {
    _itemKeys.clear();
    print('🔑 Cleared all GlobalKeys');
  }

  Future<void> _showAddToAlbumDialog() async {
    final totalSelected =
        _selectedAssetIds.length + _dragSelectedAssetIds.length;
    if (totalSelected == 0) return;

    try {
      // Get available albums (fresh data)
      final albums = await widget.apiService.getAllAlbums();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Add $totalSelected photos to album'),
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
    // Combine regular selected and drag selected assets
    final allSelectedIds = <String>{
      ..._selectedAssetIds,
      ..._dragSelectedAssetIds,
    };

    if (allSelectedIds.isEmpty) return;

    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Adding ${allSelectedIds.length} photos to album...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Call the API to add assets to album
      final results = await widget.apiService
          .addAssetsToAlbum(albumId, allSelectedIds.toList());

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

  Widget _buildUngroupedGrid(int columnCount) {
    return SliverMasonryGrid.count(
      crossAxisCount: columnCount,
      mainAxisSpacing: 0,
      crossAxisSpacing: 0,
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
        final asset = _assets[index];
        final isSelected = _isAssetSelected(asset.id);

        final photoGridItem = PhotoGridItem(
          key: ValueKey('grid_item_${asset.id}'),
          asset: asset,
          apiService: widget.apiService,
          isSelectionMode: _isSelectionMode,
          isSelected: isSelected,
          onSelectionToggle: () => _toggleAssetSelection(asset.id, isSelected),
          assetList: _assets,
          assetIndex: index,
        );

        return photoGridItem;
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

  bool _isAssetSelected(String assetId) {
    return _selectedAssetIds.contains(assetId) ||
        _originalSelectedAssetIds.contains(assetId) ||
        _dragSelectedAssetIds.contains(assetId);
  }

  Future<void> _loadPeople() async {
    if (!widget.apiService.isConfigured) return;

    try {
      final people = await widget.apiService.getAllPeople();
      if (mounted) {
        setState(() {
          _people = people;
          _filteredPeople = people;
        });
      }
    } catch (e) {
      print('Error loading people: $e');
      // Handle error appropriately, maybe show a snackbar
    }
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
