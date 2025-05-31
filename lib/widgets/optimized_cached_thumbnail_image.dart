import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import '../services/thumbnail_cache_service.dart';
import '../services/background_thumbnail_service.dart';
import '../services/immich_api_service.dart';

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

  Uint8List? _imageBytes;
  bool _isLoading = true;
  bool _hasError = false;
  bool _priorityRequested = false;

  @override
  void initState() {
    super.initState();
    _loadImageOptimized();
  }

  @override
  void didUpdateWidget(OptimizedCachedThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId) {
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
        setState(() {
          _imageBytes = cachedBytes;
          _isLoading = false;
          _hasError = false;
        });
        return;
      }

      // SECOND: If not in cache, request priority download
      if (!_priorityRequested && mounted) {
        _priorityRequested = true;

        // Request this asset to be prioritized in the background download queue
        await _backgroundService
            .prioritizeAssets([widget.assetId], widget.apiService);

        // Try again after a short delay to see if priority download completed
        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;

        final priorityBytes = await _backgroundService.getCachedAssetThumbnail(
          widget.assetId,
          widget.apiService,
        );

        if (priorityBytes != null && mounted) {
          setState(() {
            _imageBytes = priorityBytes;
            _isLoading = false;
            _hasError = false;
          });
          return;
        }
      }

      // THIRD: Last resort - download immediately (fallback for when background service isn't working)
      // Only do this if we're still loading and don't have cached data
      if (_isLoading && mounted) {
        debugPrint(
            '⚠️ Fallback: downloading thumbnail immediately for asset ${widget.assetId}');

        final thumbnailUrl = widget.apiService.getThumbnailUrl(widget.assetId);
        final downloadedBytes = await _cacheService.downloadAndCacheThumbnail(
          thumbnailUrl,
          widget.apiService.authHeaders,
        );

        if (downloadedBytes != null && mounted) {
          setState(() {
            _imageBytes = downloadedBytes;
            _isLoading = false;
            _hasError = false;
          });
          return;
        }

        // Try fallback URL if primary failed
        final fallbackUrl =
            widget.apiService.getThumbnailUrlFallback(widget.assetId);
        final fallbackBytes = await _cacheService.downloadAndCacheThumbnail(
          fallbackUrl,
          widget.apiService.authHeaders,
        );

        if (fallbackBytes != null && mounted) {
          setState(() {
            _imageBytes = fallbackBytes;
            _isLoading = false;
            _hasError = false;
          });
          return;
        }
      }

      // All attempts failed
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading optimized cached thumbnail: $e');
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
                Colors.grey.shade200,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
            ),
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
                  Icons.broken_image,
                  color: Colors.grey.shade400,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  'Failed to load',
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
