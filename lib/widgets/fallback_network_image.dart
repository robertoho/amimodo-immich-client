import 'package:flutter/material.dart';
import 'cached_thumbnail_image.dart';

class FallbackNetworkImage extends StatelessWidget {
  final String primaryUrl;
  final String fallbackUrl;
  final Map<String, String> headers;
  final BoxFit fit;
  final Color? placeholderColor;
  final Color? backgroundColor;

  const FallbackNetworkImage({
    super.key,
    required this.primaryUrl,
    required this.fallbackUrl,
    required this.headers,
    this.fit = BoxFit.cover,
    this.placeholderColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return CachedThumbnailImage(
      imageUrl: primaryUrl,
      fallbackUrl: fallbackUrl,
      headers: headers,
      fit: fit,
      backgroundColor: backgroundColor,
      placeholderColor: placeholderColor,
      placeholder: Container(
        color: backgroundColor ?? Colors.grey.shade200,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: placeholderColor ?? Colors.grey,
          ),
        ),
      ),
      errorWidget: Container(
        color: backgroundColor ?? Colors.grey.shade200,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image,
              color: Colors.grey.shade400,
              size: 32,
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
      ),
    );
  }
}
