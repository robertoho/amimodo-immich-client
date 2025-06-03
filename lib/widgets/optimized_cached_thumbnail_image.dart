import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import '../services/thumbnail_cache_service.dart';
import '../services/background_thumbnail_service.dart';
import '../services/immich_api_service.dart';
import 'dart:async';

class OptimizedCachedThumbnailImage extends StatefulWidget {
  final String assetId;
  final ImmichApiService apiService;
  final BoxFit fit;
  final Color? backgroundColor;
  final Color? placeholderColor;
  final Widget? placeholder;
  final Widget? errorWidget;

  const OptimizedCachedThumbnailImage({
    super.key,
    required this.assetId,
    required this.apiService,
    this.fit = BoxFit.cover,
    this.backgroundColor,
    this.placeholderColor,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<OptimizedCachedThumbnailImage> createState() =>
      _OptimizedCachedThumbnailImageState();
}

class _OptimizedCachedThumbnailImageState
    extends State<OptimizedCachedThumbnailImage> {
  final ThumbnailCacheService _cacheService = ThumbnailCacheService();
  final BackgroundThumbnailService _backgroundService =
      BackgroundThumbnailService();

  // Static counter to track thumbnails loaded from database
  static int _totalThumbnailsLoadedFromDB = 0;

  static void _logThumbnailStats(String assetId, int bytes, String source) {
    _totalThumbnailsLoadedFromDB++;
    // debugPrint(
    //   '$source for asset $assetId (${bytes} bytes) [Total from DB: $_totalThumbnailsLoadedFromDB]');

    // Log summary every 50 thumbnails
    if (_totalThumbnailsLoadedFromDB % 50 == 0) {
      debugPrint(
          '📊 MILESTONE: $_totalThumbnailsLoadedFromDB thumbnails loaded from Hive database');
    }
  }

  Uint8List? _imageBytes;
  bool _isLoading = true;
  bool _hasError = false;
  bool _priorityRequested = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _loadImageOptimized();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(OptimizedCachedThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId) {
      _retryTimer?.cancel();
      _imageBytes = null;
      _isLoading = true;
      _hasError = false;
      _priorityRequested = false;
      _loadImageOptimized();
    }
  }

  Future<void> _loadImageOptimized() async {
    if (!mounted) return;

    try {
      // FIRST: Try to get from cache (local database)
      final cachedBytes = await _backgroundService.getCachedAssetThumbnail(
        widget.assetId,
        widget.apiService,
      );

      if (cachedBytes != null && mounted) {
        _logThumbnailStats(widget.assetId, cachedBytes.length, '✅');
        setState(() {
          _imageBytes = cachedBytes;
          _isLoading = false;
          _hasError = false;
        });
        return;
      }

      // SECOND: If not in cache, request priority download and wait for it
      if (!_priorityRequested && mounted) {
        _priorityRequested = true;

        // Request this asset to be prioritized in the background download queue
        await _backgroundService
            .prioritizeAssets([widget.assetId], widget.apiService);

        // Wait a bit longer for priority download to complete
        await Future.delayed(const Duration(milliseconds: 1000));

        if (!mounted) return;

        final priorityBytes = await _backgroundService.getCachedAssetThumbnail(
          widget.assetId,
          widget.apiService,
        );

        if (priorityBytes != null && mounted) {
          _logThumbnailStats(widget.assetId, priorityBytes.length, '⚡');
          setState(() {
            _imageBytes = priorityBytes;
            _isLoading = false;
            _hasError = false;
          });
          return;
        }

        // Try a few more times with longer delays for slow connections
        for (int attempt = 0; attempt < 3; attempt++) {
          await Future.delayed(const Duration(milliseconds: 2000));

          if (!mounted) return;

          final delayedBytes = await _backgroundService.getCachedAssetThumbnail(
            widget.assetId,
            widget.apiService,
          );

          if (delayedBytes != null && mounted) {
            _logThumbnailStats(widget.assetId, delayedBytes.length, '⏰');
            setState(() {
              _imageBytes = delayedBytes;
              _isLoading = false;
              _hasError = false;
            });
            return;
          }
        }
      }

      // If we still don't have the thumbnail after prioritizing and waiting,
      // show placeholder but keep background service working
      // debugPrint(
      //   '📴 Thumbnail not available in database for asset ${widget.assetId}, showing placeholder');

      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });

        // Start a periodic timer to check if the thumbnail becomes available
        _retryTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
          if (!mounted) {
            timer.cancel();
            return;
          }

          final retryBytes = await _backgroundService.getCachedAssetThumbnail(
            widget.assetId,
            widget.apiService,
          );

          if (retryBytes != null && mounted) {
            timer.cancel();
            _logThumbnailStats(widget.assetId, retryBytes.length, '🔄');
            setState(() {
              _imageBytes = retryBytes;
              _isLoading = false;
              _hasError = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading thumbnail from database: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder ??
          Container(
            color: widget.backgroundColor ??
                widget.placeholderColor ??
                Colors.white,
          );
    }

    if (_hasError || _imageBytes == null) {
      return widget.errorWidget ??
          Container(
            color: widget.backgroundColor ?? Colors.grey.shade200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_download_outlined,
                  color: Colors.grey.shade400,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  'Downloading...',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          );
    }

    return Container(
      color: widget.backgroundColor,
      child: Image.memory(
        _imageBytes!,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) {
          return widget.errorWidget ??
              Container(
                color: widget.backgroundColor ?? Colors.grey.shade200,
                child: Icon(
                  Icons.broken_image,
                  color: Colors.grey.shade400,
                  size: 24,
                ),
              );
        },
      ),
    );
  }
}
