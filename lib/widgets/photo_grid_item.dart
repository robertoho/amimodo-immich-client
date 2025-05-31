import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../screens/photo_detail_screen.dart';
import 'fallback_network_image.dart';

class PhotoGridItem extends StatelessWidget {
  final ImmichAsset asset;
  final ImmichApiService apiService;

  const PhotoGridItem({
    super.key,
    required this.asset,
    required this.apiService,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PhotoDetailScreen(
              asset: asset,
              apiService: apiService,
            ),
          ),
        );
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
