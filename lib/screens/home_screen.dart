import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../widgets/photo_grid_item.dart';
import '../widgets/pinch_zoom_grid.dart';
import '../widgets/virtualized_photo_grid.dart';
import 'settings_screen.dart';
import 'albums_screen.dart';
import 'metadata_search_screen.dart';
import 'photos_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImmichApiService _apiService = ImmichApiService();
  final GridScaleService _gridScaleService = GridScaleService();
  int _selectedIndex = 0;
  bool _albumsTabVisited = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
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

  Future<void> _initializeApp() async {
    try {
      await _apiService.loadSettings();
    } catch (e) {
      // Handle initialization error
      debugPrint('Error initializing app: $e');
    }
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(apiService: _apiService),
      ),
    );

    if (result == true) {
      // Settings were saved, the virtualized grid will handle refresh automatically
      setState(() {});
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // Mark albums tab as visited when first selected
    if (index == 1) {
      _albumsTabVisited = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      _buildPhotosTab(),
      AlbumsScreen(apiService: _apiService),
      MetadataSearchScreen(apiService: _apiService),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library),
            label: 'Photos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_album),
            label: 'Albums',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Immich Photos';
      case 1:
        return 'Albums';
      case 2:
        return 'Advanced Search';
      default:
        return 'Immich Photos';
    }
  }

  Widget _buildPhotosTab() {
    return PhotosGrid(apiService: _apiService);
  }
}
