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

  // Full preload state
  int _totalAssetsDiscovered = 0;
  int _totalPagesDiscovered = 0;
  int _currentPage = 0;
  int _totalAlreadyCached = 0; // Track assets already in cache

  // Configuration
  static const int _maxConcurrentDownloads = 3;
  static const int _batchSize = 10;
  static const Duration _downloadDelay = Duration(milliseconds: 100);
  static const int _pageSize = 200; // Assets per page for full preload

  // Streams for monitoring progress
  final StreamController<BackgroundDownloadStatus> _statusController =
      StreamController<BackgroundDownloadStatus>.broadcast();

  Stream<BackgroundDownloadStatus> get statusStream => _statusController.stream;

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
  }) async {
    if (_isFullPreloadRunning) {
      debugPrint('🔄 Full preload already running');
      return;
    }

    if (!apiService.isConfigured) {
      debugPrint('❌ API service not configured, cannot start full preload');
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
        totalAssetsProcessed += result['assetsCount']!;
        totalCachedAssets += result['cached']!;
        _totalPagesDiscovered = 1;
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
        totalAssetsProcessed += result['assetsCount']!;
        totalCachedAssets += result['cached']!;
        _totalPagesDiscovered = processedPages.length;

        // Update status
        _totalAssetsDiscovered = totalAssetsProcessed;
        _totalAlreadyCached = totalCachedAssets;
        _updateStatus();

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

  /// Process a single page and return stats
  Future<Map<String, int>?> _processSinglePage(
    ImmichApiService apiService,
    int page,
    Map<String, dynamic> searchParams,
  ) async {
    _currentPage = page;
    debugPrint('🔍 Processing page $page...');

    try {
      final searchResult = await apiService.searchMetadata(
        page: page,
        size: _pageSize,
        order: searchParams['sortOrder'],
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
        personIds: searchParams['personIds'] as List<String>?,
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

      if (pageAssets.isEmpty) {
        debugPrint('📄 Page $page: No assets found');
        return null;
      }

      // Check cache status and queue uncached assets for immediate download
      final cacheStats = await _processPageAssets(pageAssets, apiService);

      debugPrint(
          '📄 Page $page: ${pageAssets.length} assets, ${cacheStats['cached']} cached, ${cacheStats['queued']} queued for download');

      // Download thumbnails for this page immediately
      if ((cacheStats['queued'] ?? 0) > 0) {
        await _downloadQueuedAssets(apiService);
      }

      return {
        'assetsCount': pageAssets.length,
        'cached': cacheStats['cached']!,
        'queued': cacheStats['queued']!,
      };
    } catch (e) {
      debugPrint('❌ Error processing page $page: $e');
      return null;
    }
  }

  /// Process assets from a single page, checking cache and queuing uncached ones
  Future<Map<String, int>> _processPageAssets(
    List<ImmichAsset> assets,
    ImmichApiService apiService,
  ) async {
    int cached = 0;
    int queued = 0;

    for (final asset in assets) {
      if (_shouldStop) break;

      final thumbnailUrl = apiService.getThumbnailUrl(asset.id);

      // Check if already cached in database
      if (await _cacheService.isCached(thumbnailUrl)) {
        cached++;
        continue;
      }

      // Check if already in our tracking (avoid duplicates)
      if (_downloadQueue.contains(asset.id) ||
          _downloading.contains(asset.id) ||
          _downloadedAssets.contains(asset.id)) {
        continue;
      }

      // Add to download queue for this page
      _downloadQueue.add(asset.id);
      queued++;
    }

    return {'cached': cached, 'queued': queued};
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

    debugPrint('🚀 Starting background thumbnail download worker');

    // Run the download worker in a separate isolate or async operation
    _downloadWorkerLoop(apiService);
  }

  Future<void> _downloadWorkerLoop(ImmichApiService apiService) async {
    while (_isRunning && !_shouldStop && _downloadQueue.isNotEmpty) {
      // Take a batch of assets to download
      final batch = _downloadQueue.take(_batchSize).toList();
      _downloadQueue.removeAll(batch);
      _downloading.addAll(batch);

      debugPrint('🔄 Processing batch of ${batch.length} thumbnails');

      // Download batch concurrently with limited concurrency
      final futures = <Future>[];
      final semaphore = Semaphore(_maxConcurrentDownloads);

      for (final assetId in batch) {
        futures.add(_downloadSingleThumbnail(assetId, apiService, semaphore));
      }

      await Future.wait(futures);

      // Remove from downloading set and add to completed
      _downloading.removeAll(batch);
      _downloadedAssets.addAll(batch);

      // Refresh cached count to reflect new downloads in database
      await _refreshCachedCount();

      _updateStatus();

      // Small delay to prevent overwhelming the system
      if (_downloadQueue.isNotEmpty) {
        await Future.delayed(_downloadDelay);
      }
    }

    _isRunning = false;
    debugPrint('✅ Background thumbnail download worker completed');

    // Final refresh of cached count
    await _refreshCachedCount();
    _updateStatus();
  }

  Future<void> _downloadSingleThumbnail(
    String assetId,
    ImmichApiService apiService,
    Semaphore semaphore,
  ) async {
    await semaphore.acquire();

    try {
      final thumbnailUrl = apiService.getThumbnailUrl(assetId);
      final fallbackUrl = apiService.getThumbnailUrlFallback(assetId);

      // Check if already cached (could have been cached by UI thread)
      if (await _cacheService.isCached(thumbnailUrl)) {
        debugPrint('✅ Thumbnail already cached for asset $assetId');
        return;
      }

      // Download and cache the thumbnail
      final bytes = await _cacheService.downloadAndCacheThumbnail(
        thumbnailUrl,
        apiService.authHeaders,
      );

      if (bytes != null) {
        //   debugPrint('✅ Successfully downloaded thumbnail for asset $assetId');
      } else {
        // Try fallback URL
        final fallbackBytes = await _cacheService.downloadAndCacheThumbnail(
          fallbackUrl,
          apiService.authHeaders,
        );

        if (fallbackBytes != null) {
          //    debugPrint(
          //      '✅ Successfully downloaded fallback thumbnail for asset $assetId');
        } else {
          debugPrint('❌ Failed to download thumbnail for asset $assetId');
        }
      }
    } catch (e) {
      debugPrint('❌ Error downloading thumbnail for asset $assetId: $e');
    } finally {
      semaphore.release();
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
    _statusController.add(currentStatus);
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
      final thumbnailUrl = apiService.getThumbnailUrl(assetId);
      if (!await _cacheService.isCached(thumbnailUrl) &&
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

/// Simple semaphore implementation for controlling concurrency
class Semaphore {
  final int maxCount;
  int _currentCount;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  Semaphore(this.maxCount) : _currentCount = maxCount;

  Future<void> acquire() async {
    if (_currentCount > 0) {
      _currentCount--;
      return;
    }

    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeFirst();
      completer.complete();
    } else {
      _currentCount++;
    }
  }
}
