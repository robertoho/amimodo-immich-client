import 'package:flutter/material.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import 'settings_screen.dart';
import 'albums_screen.dart';
import 'metadata_search_screen.dart';

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

    // Mark albums tab as visited when selected (now at index 1)
    if (index == 1) {
      _albumsTabVisited = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      MetadataSearchScreen(apiService: _apiService), // Search is now first
      AlbumsScreen(apiService: _apiService), // Albums is now second
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
            icon: Icon(Icons.search),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_album),
            label: 'Albums',
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
        return 'Advanced Search';
      case 1:
        return 'Albums';
      default:
        return 'Advanced Search';
    }
  }
}
