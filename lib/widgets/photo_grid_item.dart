import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../screens/photo_detail_screen.dart';
import 'fallback_network_image.dart';

class PhotoGridItem extends StatelessWidget {
  final ImmichAsset asset;
  final ImmichApiService apiService;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectionToggle;

  const PhotoGridItem({
    super.key,
    required this.asset,
    required this.apiService,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (isSelectionMode) {
          onSelectionToggle?.call();
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PhotoDetailScreen(
                asset: asset,
                apiService: apiService,
              ),
            ),
          );
        }
      },
      child: Card(
        elevation: 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 1.0, // Square aspect ratio
            child: Stack(
              fit: StackFit.expand,
              children: [
                FallbackNetworkImage(
                  primaryUrl: apiService.getThumbnailUrl(asset.id),
                  fallbackUrl: apiService.getThumbnailUrlFallback(asset.id),
                  headers: apiService.authHeaders,
                ),
                // Selection overlay
                if (isSelectionMode)
                  Container(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                        : Colors.black.withOpacity(0.1),
                  ),
                // Video indicator
                if (asset.type.toUpperCase() == 'VIDEO')
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                // Favorite indicator
                if (asset.isFavorite)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.red,
                        size: 16,
                      ),
                    ),
                  ),
                // Selection indicator
                if (isSelectionMode)
                  Positioned(
                    top: 8,
                    right: isSelected
                        ? 8
                        : (asset.type.toUpperCase() == 'VIDEO' ? 32 : 8),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white.withOpacity(0.8),
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
                // Date overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black54,
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      _formatDate(asset.createdAt),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
