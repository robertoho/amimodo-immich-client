import 'dart:async';
import 'dart:collection';
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
  final Set<String> _downloadedAssets = {};

  // Control flags
  bool _isRunning = false;
  bool _shouldStop = false;

  // Configuration
  static const int _maxConcurrentDownloads = 3;
  static const int _batchSize = 10;
  static const Duration _downloadDelay = Duration(milliseconds: 100);

  // Streams for monitoring progress
  final StreamController<BackgroundDownloadStatus> _statusController =
      StreamController<BackgroundDownloadStatus>.broadcast();

  Stream<BackgroundDownloadStatus> get statusStream => _statusController.stream;

  /// Start background downloading for a list of assets
  Future<void> startBackgroundDownload(
    List<ImmichAsset> assets,
    ImmichApiService apiService,
  ) async {
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

      _updateStatus();

      // Small delay to prevent overwhelming the system
      if (_downloadQueue.isNotEmpty) {
        await Future.delayed(_downloadDelay);
      }
    }

    _isRunning = false;
    debugPrint('✅ Background thumbnail download worker completed');
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
        debugPrint('✅ Successfully downloaded thumbnail for asset $assetId');
      } else {
        // Try fallback URL
        final fallbackBytes = await _cacheService.downloadAndCacheThumbnail(
          fallbackUrl,
          apiService.authHeaders,
        );

        if (fallbackBytes != null) {
          debugPrint(
              '✅ Successfully downloaded fallback thumbnail for asset $assetId');
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
    return BackgroundDownloadStatus(
      isRunning: _isRunning,
      queueSize: _downloadQueue.length,
      downloading: _downloading.length,
      completed: _downloadedAssets.length,
      isPaused: _shouldStop && _downloadQueue.isNotEmpty,
    );
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

  const BackgroundDownloadStatus({
    required this.isRunning,
    required this.queueSize,
    required this.downloading,
    required this.completed,
    required this.isPaused,
  });

  int get total => queueSize + downloading + completed;

  double get progress => total > 0 ? completed / total : 0.0;

  @override
  String toString() {
    return 'BackgroundDownloadStatus(running: $isRunning, queue: $queueSize, downloading: $downloading, completed: $completed, paused: $isPaused)';
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
