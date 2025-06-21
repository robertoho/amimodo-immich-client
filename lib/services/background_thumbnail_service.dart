import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../services/thumbnail_cache_service.dart';

class BackgroundThumbnailService {
  static final BackgroundThumbnailService _instance =
      BackgroundThumbnailService._internal();
  factory BackgroundThumbnailService() => _instance;
  BackgroundThumbnailService._internal();

  final ThumbnailCacheService _cacheService = ThumbnailCacheService();

  // Queue management
  final Set<String> _downloadQueue = {};
  final Set<String> _downloading = {};
  final Set<String> _downloadedAssets = {}; // Only session downloads

  // Cache-aware tracking
  int _totalCachedThumbnails = 0; // Total thumbnails in Hive database
  bool _isInitialized = false;

  // Control flags
  bool _isRunning = false;
  bool _shouldStop = false;
  bool _isFullPreloadRunning = false;
  bool _isAppInForeground = true;
  bool _isIdle = true;
  Timer? _autoPreloadTimer;

  // Full preload state
  int _totalAssetsDiscovered = 0;
  int _totalPagesDiscovered = 0;
  int _currentPage = 0;
  int _totalAlreadyCached = 0; // Track assets already in cache

  // Configuration
  static const int _maxConcurrentDownloads = 30; // Reduced for background
  static const int _batchSize = 10;
  static const Duration _downloadDelay = Duration(milliseconds: 100);
  static const int _pageSize = 200; // Assets per page for full preload
  static const Duration _idleDelay = Duration(seconds: 2); // Time to wait

  // Streams for monitoring progress
  final StreamController<BackgroundDownloadStatus> _statusController =
      StreamController<BackgroundDownloadStatus>.broadcast();

  Stream<BackgroundDownloadStatus> get statusStream => _statusController.stream;

  // Method to be called when app goes to background
  void onAppBackground() {
    _isAppInForeground = false;
    pauseIdlePreload();
    debugPrint('App in background, pausing idle preload');
  }

  // Method to be called when app comes to foreground
  void onAppForeground() {
    _isAppInForeground = true;
    resumeIdlePreload();
    debugPrint('App in foreground, resuming idle preload');
  }

  /// Call this when user starts an activity (scrolling, searching)
  void notifyAppIsBusy() {
    _isIdle = false;
    cancelIdlePreloadTimer(); // Cancel any pending timer
    if (_isFullPreloadRunning) {
      pauseIdlePreload();
      debugPrint('App is busy, pausing ongoing idle preload');
    }
  }

  /// Call this when user activity stops
  void notifyAppIsIdle(ImmichApiService apiService) {
    _isIdle = true;
    if (_isFullPreloadRunning) {
      resumeIdlePreload();
      debugPrint('App is idle, resuming ongoing preload');
    } else {
      // If no preload is running, start a timer to begin one
      startIdlePreloadTimer(apiService);
    }
  }

  /// Start a timer to begin full preload if app remains idle
  void startIdlePreloadTimer(ImmichApiService apiService) {
    cancelIdlePreloadTimer(); // Ensure no other timer is running
    if (!_isAppInForeground || _isFullPreloadRunning) return;

    debugPrint('Starting idle timer for full preload...');
    _autoPreloadTimer = Timer(_idleDelay, () {
      if (_isIdle && _isAppInForeground && !_isFullPreloadRunning) {
        debugPrint('Idle timer expired, starting full preload automatically');
        // Start a full preload with default filters
        startFullPreload(apiService);
      }
    });
  }

  /// Cancel the idle preload timer
  void cancelIdlePreloadTimer() {
    if (_autoPreloadTimer?.isActive ?? false) {
      _autoPreloadTimer!.cancel();
      debugPrint('Cancelled idle preload timer');
    }
  }

  /// Pause the idle preload process
  void pauseIdlePreload() {
    if (_isFullPreloadRunning) {
      _shouldStop = true;
      debugPrint('Pausing idle preload');
    }
  }

  /// Resume the idle preload process
  void resumeIdlePreload() {
    if (_isFullPreloadRunning) {
      _shouldStop = false;
      debugPrint('Resuming idle preload');
      // Here you might need to re-trigger the download loop if it was fully stopped
    }
  }

  /// Initialize the service and restore cached thumbnail count
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Get the count of thumbnails already cached in Hive database
      _totalCachedThumbnails = await _cacheService.getCachedThumbnailCount();

      debugPrint(
          '📊 BackgroundThumbnailService initialized: $_totalCachedThumbnails thumbnails in cache');

      _isInitialized = true;
      _updateStatus();
    } catch (e) {
      debugPrint('❌ Error initializing BackgroundThumbnailService: $e');
      _totalCachedThumbnails = 0;
      _isInitialized = true;
    }
  }

  /// Start full preload of ALL thumbnails from ALL pages, starting from current position
  Future<void> startFullPreload(
    ImmichApiService apiService, {
    // Starting position (asset index) to prioritize nearby assets
    int startIndex = 0,
    // Search filters to match the current search
    bool? isFavorite,
    bool? isOffline,
    bool? isTrashed,
    bool? isArchived,
    bool withDeleted = false,
    bool withArchived = false,
    String? type,
    String? city,
    String? country,
    String? make,
    String? model,
    String? sortOrder,
    List<String>? personIds,
    bool autoStart = true, // To control if preload starts immediately
  }) async {
    if (_isFullPreloadRunning) {
      debugPrint('🔄 Full preload already running');
      return;
    }

    if (!apiService.isConfigured) {
      debugPrint('❌ API service not configured, cannot start full preload');
      return;
    }

    if (!autoStart) {
      debugPrint('Preload configured but not auto-started. Waiting for idle.');
      // Update status to show that a preload is pending
      _updateStatus();
      return;
    }

    // Ensure service is initialized
    await initialize();

    _isFullPreloadRunning = true;
    _shouldStop = false;
    _totalAssetsDiscovered = 0;
    _totalPagesDiscovered = 0;
    _currentPage = 0;
    _totalAlreadyCached = 0;

    // Reset session downloads but keep cached count
    _downloadedAssets.clear();

    debugPrint(
        '🚀 Starting full thumbnail preload from position $startIndex - expanding outward...');
    debugPrint('📊 Currently have $_totalCachedThumbnails thumbnails in cache');

    try {
      // Process pages starting from current position, expanding outward
      await _processAllPagesWithDownloadFromPosition(apiService, startIndex, {
        'isFavorite': isFavorite,
        'isOffline': isOffline,
        'isTrashed': isTrashed,
        'isArchived': isArchived,
        'withDeleted': withDeleted,
        'withArchived': withArchived,
        'type': type,
        'city': city,
        'country': country,
        'make': make,
        'model': model,
        'sortOrder': sortOrder,
        'personIds': personIds,
      });
    } catch (e) {
      debugPrint('❌ Error during full preload: $e');
    } finally {
      _isFullPreloadRunning = false;
      // Final refresh of cached count
      await _refreshCachedCount();
      _updateStatus();
      debugPrint(
          '✅ Full thumbnail preload completed - now have $_totalCachedThumbnails thumbnails in cache');
    }
  }

  /// Process all pages starting from current position, expanding outward in both directions
  Future<void> _processAllPagesWithDownloadFromPosition(
    ImmichApiService apiService,
    int startIndex,
    Map<String, dynamic> searchParams,
  ) async {
    // Calculate starting page from asset index
    final startPage = (startIndex / _pageSize).floor() + 1;
    debugPrint(
        '📍 Starting from page $startPage (based on asset index $startIndex)');

    // Track which pages we've processed to avoid duplicates
    final Set<int> processedPages = {};
    int totalAssetsProcessed = 0;
    int totalCachedAssets = 0;

    // First, process the starting page
    if (!_shouldStop) {
      final result =
          await _processSinglePage(apiService, startPage, searchParams);
      if (result != null) {
        processedPages.add(startPage);
        totalAssetsProcessed += result['assetsCount'] as int;
        totalCachedAssets += result['cached'] as int;
        _totalPagesDiscovered = 1;

        // Start download for this page's assets
        if (result['assets'] != null) {
          await startBackgroundDownload(result['assets']!, apiService);
        }
      }
    }

    // Then expand outward: alternate between forward and backward pages
    int forwardPage = startPage + 1;
    int backwardPage = startPage - 1;
    bool hasForwardData = true;
    bool hasBackwardData = backwardPage > 0;

    int direction = 1; // 1 for forward, -1 for backward

    while (!_shouldStop && (hasForwardData || hasBackwardData)) {
      int currentPage;
      bool isForward;

      // Alternate between forward and backward direction
      if (direction == 1 && hasForwardData) {
        currentPage = forwardPage;
        isForward = true;
        forwardPage++;
      } else if (direction == -1 && hasBackwardData) {
        currentPage = backwardPage;
        isForward = false;
        backwardPage--;
        hasBackwardData = backwardPage > 0;
      } else {
        // If one direction is exhausted, continue with the other
        if (hasForwardData) {
          currentPage = forwardPage;
          isForward = true;
          forwardPage++;
        } else if (hasBackwardData) {
          currentPage = backwardPage;
          isForward = false;
          backwardPage--;
          hasBackwardData = backwardPage > 0;
        } else {
          break;
        }
      }

      // Skip if already processed
      if (processedPages.contains(currentPage)) {
        direction *= -1; // Switch direction
        continue;
      }

      // Process the page
      final result =
          await _processSinglePage(apiService, currentPage, searchParams);
      if (result != null) {
        processedPages.add(currentPage);
        totalAssetsProcessed += result['assetsCount'] as int;
        totalCachedAssets += result['cached'] as int;
        _totalPagesDiscovered = processedPages.length;

        // Update status
        _totalAssetsDiscovered = totalAssetsProcessed;
        _totalAlreadyCached = totalCachedAssets;
        _updateStatus();

        // Start download for this page's assets
        if (result['assets'] != null) {
          await startBackgroundDownload(result['assets']!, apiService);
        }

        // Check if this direction still has data
        if (isForward && result['assetsCount']! < _pageSize) {
          hasForwardData = false;
        }
      } else {
        // No data found, stop this direction
        if (isForward) {
          hasForwardData = false;
        } else {
          hasBackwardData = false;
        }
      }

      // Switch direction for next iteration
      direction *= -1;

      // Small delay between pages to not overwhelm the server
      if (!_shouldStop && (hasForwardData || hasBackwardData)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    final assetsToDownload = totalAssetsProcessed - totalCachedAssets;
    debugPrint(
        '📊 Processing complete: $totalAssetsProcessed total assets, $totalCachedAssets already cached, $assetsToDownload downloaded');
  }

  /// Process a single page of assets and return statistics
  Future<Map<String, dynamic>?> _processSinglePage(
    ImmichApiService apiService,
    int page,
    Map<String, dynamic> searchParams,
  ) async {
    try {
      // Use the searchMetadata endpoint for more flexible filtering
      final searchResult = await apiService.searchMetadata(
        page: page,
        size: _pageSize,
        isFavorite: searchParams['isFavorite'],
        isOffline: searchParams['isOffline'],
        isTrashed: searchParams['isTrashed'],
        isArchived: searchParams['isArchived'],
        withDeleted: searchParams['withDeleted'],
        withArchived: searchParams['withArchived'],
        type: searchParams['type'],
        city: searchParams['city'],
        country: searchParams['country'],
        make: searchParams['make'],
        model: searchParams['model'],
        personIds: searchParams['personIds'],
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

      final pageAssets =
          jsonList.map((json) => ImmichAsset.fromJson(json)).toList();

      if (pageAssets.isEmpty && page > 1) {
        // No more assets to fetch
        return null;
      }

      _currentPage = page;

      final assetsToDownload = <ImmichAsset>[];
      int alreadyCachedCount = 0;

      // Check each asset for caching status
      for (final asset in pageAssets) {
        final thumbnailUrl = apiService.getThumbnailUrl(asset.id);
        if (await _cacheService.isCachedAndUpToDate(
            thumbnailUrl, asset.modifiedAt)) {
          alreadyCachedCount++;
        } else {
          assetsToDownload.add(asset);
        }
      }

      debugPrint(
          '📄 Page $page: Found ${pageAssets.length} assets, $alreadyCachedCount already cached, ${assetsToDownload.length} to download');

      return {
        'assetsCount': pageAssets.length,
        'cached': alreadyCachedCount,
        'assets': assetsToDownload, // Return assets to be queued
      };
    } catch (e) {
      debugPrint('❌ Error processing page $page: $e');
      return null;
    }
  }

  /// Download all currently queued assets and wait for completion
  Future<void> _downloadQueuedAssets(ImmichApiService apiService) async {
    if (_downloadQueue.isEmpty) return;

    debugPrint(
        '📥 Downloading ${_downloadQueue.length} uncached thumbnails from current page...');

    // Start download worker if not already running
    if (!_isRunning && _downloadQueue.isNotEmpty) {
      _startDownloadWorker(apiService);
    }

    // Wait for all queued assets to be processed
    while (_isRunning && _downloadQueue.isNotEmpty && !_shouldStop) {
      _updateStatus();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    debugPrint('✅ Page download completed');
  }

  /// Stop full preload
  void stopFullPreload() {
    _shouldStop = true;
    _isFullPreloadRunning = false;
    debugPrint('🛑 Stopping full thumbnail preload');
    _updateStatus();
  }

  /// Start background downloading for a list of assets
  Future<void> startBackgroundDownload(
    List<ImmichAsset> assets,
    ImmichApiService apiService,
  ) async {
    // Ensure service is initialized
    await initialize();

    if (_isRunning) {
      debugPrint('🔄 Background download already running, adding to queue');
    }

    // Add new assets to download queue (only if not already cached or downloading)
    final newAssets = <String>[];
    for (final asset in assets) {
      final thumbnailUrl = apiService.getThumbnailUrl(asset.id);
      if (!await _cacheService.isCached(thumbnailUrl) &&
          !_downloadQueue.contains(asset.id) &&
          !_downloading.contains(asset.id) &&
          !_downloadedAssets.contains(asset.id)) {
        _downloadQueue.add(asset.id);
        newAssets.add(asset.id);
      }
    }

    debugPrint(
        '📥 Added ${newAssets.length} new assets to download queue. Total queue: ${_downloadQueue.length}');

    if (!_isRunning && _downloadQueue.isNotEmpty) {
      _startDownloadWorker(apiService);
    }

    _updateStatus();
  }

  /// Start the background download worker
  void _startDownloadWorker(ImmichApiService apiService) {
    if (_isRunning) return;

    _isRunning = true;
    _shouldStop = false;

    debugPrint('🚀 Started download worker');
    _updateStatus();

    // Create worker pool
    final workers = <Future<void>>[];
    for (int i = 0; i < _maxConcurrentDownloads; i++) {
      workers.add(_downloadWorker(apiService));
    }

    // Wait for all workers to finish
    Future.wait(workers).then((_) {
      _isRunning = false;
      debugPrint('🏁 All download workers finished');

      // If there are still items in the queue, restart the worker
      // This can happen if items were added while workers were running
      if (_downloadQueue.isNotEmpty && !_shouldStop) {
        debugPrint('Restarting download worker for remaining items...');
        _startDownloadWorker(apiService);
      } else {
        _updateStatus();
      }
    });
  }

  // The worker task
  Future<void> _downloadWorker(ImmichApiService apiService) async {
    while (_downloadQueue.isNotEmpty && !_shouldStop) {
      final assetId = _downloadQueue.first;
      _downloadQueue.remove(assetId);

      // Check again before downloading
      if (_downloading.contains(assetId) ||
          _downloadedAssets.contains(assetId)) {
        continue;
      }

      // TODO: This is inefficient as we refetch asset info.
      // We should ideally pass the full ImmichAsset object to the queue.
      // For now, we'll have to fetch asset details.
      // This part needs optimization later.
      final asset = await apiService.getAssetDetails(assetId);

      if (asset == null) {
        debugPrint('❌ Could not find asset details for ID: $assetId');
        continue;
      }

      _downloading.add(assetId);
      _updateStatus();

      final thumbnailUrl = apiService.getThumbnailUrl(assetId);
      final headers = apiService.authHeaders;

      try {
        final thumbnailData = await _cacheService.downloadAndCacheThumbnail(
          thumbnailUrl,
          headers,
          asset.modifiedAt,
        );

        if (thumbnailData != null) {
          _downloadedAssets.add(assetId);
          debugPrint('✅ Downloaded thumbnail for asset $assetId');
        } else {
          debugPrint('⚠️ Failed to download thumbnail for asset $assetId');
        }
      } catch (e) {
        debugPrint('❌ Error downloading thumbnail for $assetId: $e');
        // Optional: Add back to queue for retry?
      } finally {
        _downloading.remove(assetId);
        _updateStatus();
      }

      await Future.delayed(_downloadDelay);
    }
  }

  /// Stop background downloading
  void stopBackgroundDownload() {
    _shouldStop = true;
    debugPrint('🛑 Stopping background thumbnail download');
    _updateStatus();
  }

  /// Pause background downloading
  void pauseBackgroundDownload() {
    _shouldStop = true;
    debugPrint('⏸️ Pausing background thumbnail download');
    _updateStatus();
  }

  /// Resume background downloading
  void resumeBackgroundDownload(ImmichApiService apiService) {
    if (_downloadQueue.isNotEmpty && !_isRunning) {
      debugPrint('▶️ Resuming background thumbnail download');
      _startDownloadWorker(apiService);
    }
  }

  /// Clear all queues and reset state
  void clearQueues() {
    _downloadQueue.clear();
    _downloading.clear();
    _downloadedAssets.clear();
    debugPrint('🧹 Cleared all download queues');
    _updateStatus();
  }

  /// Get current status
  BackgroundDownloadStatus get currentStatus {
    // Ensure we're initialized before providing status
    if (!_isInitialized) {
      return BackgroundDownloadStatus(
        isRunning: false,
        queueSize: 0,
        downloading: 0,
        completed: 0,
        isPaused: false,
      );
    }

    // Total completed = thumbnails in cache + session downloads
    final totalCompleted = _totalCachedThumbnails + _downloadedAssets.length;

    return BackgroundDownloadStatus(
      isRunning: _isRunning,
      queueSize: _downloadQueue.length,
      downloading: _downloading.length,
      completed: totalCompleted,
      isPaused: _shouldStop && _downloadQueue.isNotEmpty,
      // Full preload information
      isFullPreloadRunning: _isFullPreloadRunning,
      totalAssetsDiscovered: _totalAssetsDiscovered,
      totalPagesDiscovered: _totalPagesDiscovered,
      currentPage: _currentPage,
      totalAlreadyCached: _totalAlreadyCached,
    );
  }

  /// Refresh the cached thumbnail count from database
  Future<void> _refreshCachedCount() async {
    try {
      _totalCachedThumbnails = await _cacheService.getCachedThumbnailCount();
    } catch (e) {
      debugPrint('❌ Error refreshing cached count: $e');
    }
  }

  void _updateStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(currentStatus);
    }
  }

  /// Check if a specific asset thumbnail is available locally
  Future<bool> isAssetThumbnailCached(
      String assetId, ImmichApiService apiService) async {
    final thumbnailUrl = apiService.getThumbnailUrl(assetId);
    return await _cacheService.isCached(thumbnailUrl);
  }

  /// Get cached thumbnail for an asset
  Future<Uint8List?> getCachedAssetThumbnail(
      String assetId, ImmichApiService apiService) async {
    final thumbnailUrl = apiService.getThumbnailUrl(assetId);
    return await _cacheService.getCachedThumbnail(thumbnailUrl);
  }

  /// Prioritize certain assets for immediate download
  Future<void> prioritizeAssets(
      List<String> assetIds, ImmichApiService apiService) async {
    final priorityAssets = <String>[];

    for (final assetId in assetIds) {
      final asset = await apiService.getAssetDetails(assetId);
      if (asset == null) continue;

      final thumbnailUrl = apiService.getThumbnailUrl(assetId);
      if (!await _cacheService.isCachedAndUpToDate(
              thumbnailUrl, asset.modifiedAt) &&
          !_downloading.contains(assetId)) {
        priorityAssets.add(assetId);
      }
    }

    if (priorityAssets.isNotEmpty) {
      // Add priority assets to the front of the queue
      final newQueue = <String>{...priorityAssets, ..._downloadQueue};
      _downloadQueue.clear();
      _downloadQueue.addAll(newQueue);

      debugPrint('⚡ Prioritized ${priorityAssets.length} assets for download');

      // Start worker if not running
      if (!_isRunning && _downloadQueue.isNotEmpty) {
        _startDownloadWorker(apiService);
      }
    }
  }

  void dispose() {
    _shouldStop = true;
    _autoPreloadTimer?.cancel();
    _statusController.close();
  }
}

/// Status information for background downloads
class BackgroundDownloadStatus {
  final bool isRunning;
  final int queueSize;
  final int downloading;
  final int completed;
  final bool isPaused;

  // Full preload status
  final bool isFullPreloadRunning;
  final int totalAssetsDiscovered;
  final int totalPagesDiscovered;
  final int currentPage;
  final int totalAlreadyCached;

  const BackgroundDownloadStatus({
    required this.isRunning,
    required this.queueSize,
    required this.downloading,
    required this.completed,
    required this.isPaused,
    this.isFullPreloadRunning = false,
    this.totalAssetsDiscovered = 0,
    this.totalPagesDiscovered = 0,
    this.currentPage = 0,
    this.totalAlreadyCached = 0,
  });

  int get total => queueSize + downloading + completed;

  double get progress => total > 0 ? completed / total : 0.0;

  double get fullPreloadProgress {
    final needToDownload = totalAssetsDiscovered - totalAlreadyCached;
    return needToDownload > 0 ? completed / needToDownload : 1.0;
  }

  String get fullPreloadStatusText {
    if (!isFullPreloadRunning && totalAssetsDiscovered == 0) {
      return 'Full preload not started';
    } else if (isFullPreloadRunning && totalPagesDiscovered == 0) {
      return 'Starting bidirectional preload from current position...';
    } else if (isFullPreloadRunning) {
      final needToDownload = totalAssetsDiscovered - totalAlreadyCached;
      return 'Expanding outward from start position - Page $currentPage (${completed}/${needToDownload} downloaded, ${totalAlreadyCached} cached)';
    } else {
      final needToDownload = totalAssetsDiscovered - totalAlreadyCached;
      return 'Bidirectional preload completed: ${completed}/${needToDownload} downloaded, ${totalAlreadyCached} were already cached';
    }
  }

  @override
  String toString() {
    return 'BackgroundDownloadStatus(running: $isRunning, queue: $queueSize, downloading: $downloading, completed: $completed, paused: $isPaused, fullPreload: $isFullPreloadRunning, totalDiscovered: $totalAssetsDiscovered, cached: $totalAlreadyCached, page: $currentPage/$totalPagesDiscovered)';
  }
}
