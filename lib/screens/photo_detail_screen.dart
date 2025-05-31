import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../widgets/fallback_network_image.dart';

class PhotoDetailScreen extends StatefulWidget {
  final List<ImmichAsset> assets;
  final int initialIndex;
  final ImmichApiService apiService;

  const PhotoDetailScreen({
    super.key,
    required this.assets,
    required this.initialIndex,
    required this.apiService,
  });

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  ImmichAsset get _currentAsset => widget.assets[_currentIndex];

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.assets.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _goToPrevious();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _goToNext();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: widget.assets.length > 1
              ? Text(
                  '${_currentIndex + 1} of ${widget.assets.length}',
                  style: const TextStyle(color: Colors.white),
                )
              : null,
          centerTitle: true,
          actions: [
            if (_currentAsset.isFavorite)
              const Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: Icon(Icons.favorite, color: Colors.red),
              ),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: PageView.builder(
          controller: _pageController,
          itemCount: widget.assets.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          itemBuilder: (context, index) {
            final asset = widget.assets[index];
            return Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: FallbackNetworkImage(
                  primaryUrl: widget.apiService.getAssetUrl(asset.id),
                  fallbackUrl: widget.apiService.getAssetUrlFallback(asset.id),
                  headers: widget.apiService.authHeaders,
                  fit: BoxFit.contain,
                  backgroundColor: Colors.black,
                  placeholderColor: Colors.white,
                ),
              ),
            );
          },
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black54,
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_currentAsset.description != null &&
                    _currentAsset.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      _currentAsset.description!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Icon(
                      _currentAsset.type.toUpperCase() == 'VIDEO'
                          ? Icons.videocam
                          : Icons.photo,
                      color: Colors.grey.shade300,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(_currentAsset.createdAt),
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (widget.assets.length > 1) ...[
                      // Navigation hints for keyboard users
                      Icon(
                        Icons.keyboard_arrow_left,
                        color: _currentIndex > 0
                            ? Colors.grey.shade300
                            : Colors.grey.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_right,
                        color: _currentIndex < widget.assets.length - 1
                            ? Colors.grey.shade300
                            : Colors.grey.shade600,
                        size: 20,
                      ),
                      const SizedBox(width: 16),
                    ],
                    if (_currentAsset.isFavorite)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red, width: 1),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.favorite,
                              color: Colors.red,
                              size: 12,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Favorite',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
