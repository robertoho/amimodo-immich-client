import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/immich_album.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../widgets/photo_grid_item.dart';
import '../widgets/pinch_zoom_grid.dart';

class AlbumDetailScreen extends StatefulWidget {
  final ImmichAlbum album;
  final ImmichApiService apiService;

  const AlbumDetailScreen({
    super.key,
    required this.album,
    required this.apiService,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final GridScaleService _gridScaleService = GridScaleService();
  List<ImmichAsset> _assets = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadAlbumAssets();
    _gridScaleService.addListener(_onGridScaleChanged);
  }

  @override
  void dispose() {
    _gridScaleService.removeListener(_onGridScaleChanged);
    super.dispose();
  }

  void _onGridScaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadAlbumAssets() async {
    if (!widget.apiService.isConfigured) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Please configure your Immich server settings';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final assets = await widget.apiService.getAlbumAssets(widget.album.id);
      setState(() {
        _assets = assets;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _refreshAssets() async {
    await _loadAlbumAssets();
  }

  int _getGridColumnCount(double width) {
    return _gridScaleService.getGridColumnCount(width);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.album.albumName),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _refreshAssets,
              tooltip: 'Refresh album',
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading album photos...'),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _refreshAssets,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_assets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_album_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Empty Album',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'This album doesn\'t contain any photos yet',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refreshAssets,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Album info header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.shade300,
                width: 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.album.albumName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.photo,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_assets.length} ${_assets.length == 1 ? 'photo' : 'photos'}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  if (widget.album.shared) ...[
                    Icon(
                      Icons.people,
                      size: 16,
                      color: Colors.blue.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Shared',
                      style: TextStyle(
                        color: Colors.blue.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (widget.album.hasSharedLink) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.link,
                      size: 16,
                      color: Colors.orange.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Public Link',
                      style: TextStyle(
                        color: Colors.orange.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              if (widget.album.description != null &&
                  widget.album.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  widget.album.description!,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Photos grid
        Expanded(
          child: PinchZoomGrid(
            child: RefreshIndicator(
              onRefresh: _refreshAssets,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columnCount = _getGridColumnCount(constraints.maxWidth);
                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(16.0),
                        sliver: SliverMasonryGrid.count(
                          crossAxisCount: columnCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childCount: _assets.length,
                          itemBuilder: (context, index) {
                            return PhotoGridItem(
                              asset: _assets[index],
                              apiService: widget.apiService,
                              assetList: _assets,
                              assetIndex: index,
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
