import 'package:flutter/material.dart';
import '../models/immich_album.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../widgets/album_grid_item.dart';
import '../widgets/pinch_zoom_grid.dart';

class AlbumsScreen extends StatefulWidget {
  final ImmichApiService apiService;
  final ValueNotifier<int>? refreshNotifier;
  final VoidCallback? onOpenSettings;

  const AlbumsScreen({
    super.key,
    required this.apiService,
    this.refreshNotifier,
    this.onOpenSettings,
  });

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen>
    with AutomaticKeepAliveClientMixin {
  final GridScaleService _gridScaleService = GridScaleService();
  List<ImmichAlbum> _albums = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // Listen to refresh notifier
    widget.refreshNotifier?.addListener(_onRefreshRequested);

    // Delay loading to ensure API service is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAlbums();
    });
    _gridScaleService.addListener(_onGridScaleChanged);
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onRefreshRequested);
    _gridScaleService.removeListener(_onGridScaleChanged);
    super.dispose();
  }

  void _onGridScaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onRefreshRequested() {
    print('🔄 Albums refresh requested via notifier');
    _loadAlbums();
  }

  /// Public method to refresh albums - can be called from parent widgets
  Future<void> refreshAlbums() async {
    await _loadAlbums();
  }

  Future<void> _loadAlbums() async {
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
      final albums = await widget.apiService.getAllAlbums();
      setState(() {
        _albums = albums;
        _isLoading = false;
      });
      print('✅ Albums refreshed: ${albums.length} albums loaded');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _refreshAlbums() async {
    await _loadAlbums();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshAlbums,
            tooltip: 'Refresh albums',
          ),
          if (widget.onOpenSettings != null)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: widget.onOpenSettings,
              tooltip: 'Settings',
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: _buildBody(),
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
            Text('Loading albums...'),
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
                onPressed: _refreshAlbums,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_albums.isEmpty) {
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
              'No albums found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first album to get started',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refreshAlbums,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAlbums,
      child: PinchZoomGrid(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columnCount =
                _gridScaleService.getGridColumnCount(constraints.maxWidth);
            return GridView.builder(
              padding: EdgeInsets.only(
                left: 4.0,
                right: 4.0,
                top: 4.0 + MediaQuery.of(context).padding.top + kToolbarHeight,
                bottom: 4.0,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnCount,
                crossAxisSpacing: 0,
                mainAxisSpacing: 0,
                childAspectRatio: 0.8,
              ),
              itemCount: _albums.length,
              itemBuilder: (context, index) {
                return AlbumGridItem(
                  album: _albums[index],
                  apiService: widget.apiService,
                  onOpenSettings: widget.onOpenSettings,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
