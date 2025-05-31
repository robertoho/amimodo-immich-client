import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import '../services/thumbnail_cache_service.dart';

class CachedThumbnailImage extends StatefulWidget {
  final String imageUrl;
  final String? fallbackUrl;
  final Map<String, String>? headers;
  final BoxFit fit;
  final Color? backgroundColor;
  final Color? placeholderColor;
  final Widget? placeholder;
  final Widget? errorWidget;

  const CachedThumbnailImage({
    super.key,
    required this.imageUrl,
    this.fallbackUrl,
    this.headers,
    this.fit = BoxFit.cover,
    this.backgroundColor,
    this.placeholderColor,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<CachedThumbnailImage> createState() => _CachedThumbnailImageState();
}

class _CachedThumbnailImageState extends State<CachedThumbnailImage> {
  final ThumbnailCacheService _cacheService = ThumbnailCacheService();
  Uint8List? _imageBytes;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _imageBytes = null;
      _isLoading = true;
      _hasError = false;
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (!mounted) return;

    try {
      // First try to get from cache
      final cachedBytes =
          await _cacheService.getCachedThumbnail(widget.imageUrl);

      if (cachedBytes != null && mounted) {
        setState(() {
          _imageBytes = cachedBytes;
          _isLoading = false;
          _hasError = false;
        });
        return;
      }

      // If not cached, download and cache
      final downloadedBytes = await _cacheService.downloadAndCacheThumbnail(
        widget.imageUrl,
        widget.headers,
      );

      if (downloadedBytes != null && mounted) {
        setState(() {
          _imageBytes = downloadedBytes;
          _isLoading = false;
          _hasError = false;
        });
        return;
      }

      // If primary URL failed, try fallback
      if (widget.fallbackUrl != null && widget.fallbackUrl != widget.imageUrl) {
        final fallbackBytes = await _cacheService.downloadAndCacheThumbnail(
          widget.fallbackUrl!,
          widget.headers,
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
      debugPrint('❌ Error loading cached thumbnail: $e');
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
            child: Icon(
              Icons.broken_image,
              color: Colors.grey.shade400,
              size: 24,
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
