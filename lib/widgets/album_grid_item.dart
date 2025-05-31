import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/immich_album.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../screens/album_detail_screen.dart';
import '../widgets/fallback_network_image.dart';

class AlbumGridItem extends StatefulWidget {
  final ImmichAlbum album;
  final ImmichApiService apiService;

  const AlbumGridItem({
    super.key,
    required this.album,
    required this.apiService,
  });

  @override
  State<AlbumGridItem> createState() => _AlbumGridItemState();
}

class _AlbumGridItemState extends State<AlbumGridItem> {
  final GridScaleService _gridScaleService = GridScaleService();

  @override
  void initState() {
    super.initState();
    _gridScaleService.addListener(_onScaleChanged);
  }

  @override
  void dispose() {
    _gridScaleService.removeListener(_onScaleChanged);
    super.dispose();
  }

  void _onScaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaleFactor = _gridScaleService.scaleFactor;

    // Define thresholds for hiding elements based on scale factor
    final showDetailedText =
        scaleFactor >= 0.7; // Hide detailed text when zoomed in
    final showDescription =
        scaleFactor >= 0.5; // Hide description when heavily zoomed in
    final showSecondaryInfo =
        scaleFactor >= 0.8; // Hide secondary info (count, icons)

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AlbumDetailScreen(
              album: widget.album,
              apiService: widget.apiService,
            ),
          ),
        );
      },
      child: Card(
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album thumbnail - always visible
            Expanded(
              flex: showDetailedText
                  ? 3
                  : 4, // Give more space to image when text is hidden
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                  color: Colors.grey.shade200,
                ),
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                  child: widget.album.albumThumbnailAssetId != null
                      ? FallbackNetworkImage(
                          primaryUrl: widget.apiService.getAlbumThumbnailUrl(
                              widget.album.albumThumbnailAssetId),
                          fallbackUrl: widget.apiService
                              .getAlbumThumbnailUrlFallback(
                                  widget.album.albumThumbnailAssetId),
                          headers: widget.apiService.authHeaders,
                        )
                      : Container(
                          color: Colors.grey.shade200,
                          child: showDetailedText
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.photo_album,
                                      color: Colors.grey.shade400,
                                      size: 48,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Empty Album',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                )
                              : Icon(
                                  Icons.photo_album,
                                  color: Colors.grey.shade400,
                                  size: scaleFactor < 0.5 ? 24 : 48,
                                ),
                        ),
                ),
              ),
            ),
            // Album info - conditionally shown based on scale
            if (showDetailedText)
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Album title - always show if we're showing detailed text
                      Text(
                        widget.album.albumName,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Secondary info - conditionally shown
                      if (showSecondaryInfo) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.photo,
                              size: 14,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${widget.album.assetCount} ${widget.album.assetCount == 1 ? 'photo' : 'photos'}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.album.shared)
                              Icon(
                                Icons.people,
                                size: 14,
                                color: Colors.blue.shade600,
                              ),
                            if (widget.album.hasSharedLink)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.link,
                                  size: 14,
                                  color: Colors.orange.shade600,
                                ),
                              ),
                          ],
                        ),
                      ],
                      // Description - only show at larger scales
                      if (showDescription &&
                          widget.album.description != null &&
                          widget.album.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.album.description!,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            // Minimal info for very small scales
            if (!showDetailedText && scaleFactor >= 0.4)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Text(
                  widget.album.albumName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
