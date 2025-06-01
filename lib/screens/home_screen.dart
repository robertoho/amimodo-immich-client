import 'package:flutter/material.dart';
import '../services/immich_api_service.dart';
import '../services/grid_scale_service.dart';
import '../services/account_manager.dart';
import 'settings_screen.dart';
import 'albums_screen.dart';
import 'metadata_search_screen.dart';
import 'account_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImmichApiService _apiService = ImmichApiService();
  final GridScaleService _gridScaleService = GridScaleService();
  final AccountManager _accountManager = AccountManager();
  final ValueNotifier<int> _albumRefreshNotifier = ValueNotifier<int>(0);
  int _selectedIndex = 0;
  bool _albumsTabVisited = false;
  String? _activeAccountName;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _gridScaleService.addListener(_onGridScaleChanged);
  }

  @override
  void dispose() {
    _gridScaleService.removeListener(_onGridScaleChanged);
    _albumRefreshNotifier.dispose();
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
      await _accountManager.initialize();
      _updateActiveAccountName();
    } catch (e) {
      // Handle initialization error
      debugPrint('Error initializing app: $e');
    }
  }

  void _updateActiveAccountName() {
    final activeAccount = _accountManager.getActiveAccount();
    setState(() {
      _activeAccountName = activeAccount?.name;
    });
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(apiService: _apiService),
      ),
    );

    if (result == true) {
      // Settings were saved, the virtualized grid will handle refresh automatically
      _updateActiveAccountName();
      setState(() {});
    }
  }

  Future<void> _openAccountManagement() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AccountManagementScreen(apiService: _apiService),
      ),
    );

    if (result == true) {
      // Account was changed
      _updateActiveAccountName();
      setState(() {});
    }
  }

  void _onItemTapped(int index) {
    final previousIndex = _selectedIndex;
    setState(() {
      _selectedIndex = index;
    });

    // Refresh albums when Albums tab is selected (index 1)
    if (index == 1 && previousIndex != 1) {
      print('🔄 Albums tab selected, triggering refresh');
      _albumRefreshNotifier.value++;
    }

    // Mark albums tab as visited when selected (now at index 1)
    if (index == 1) {
      _albumsTabVisited = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      MetadataSearchScreen(
        apiService: _apiService,
        onOpenSettings: _openSettings,
      ), // Search is now first
      AlbumsScreen(
        apiService: _apiService,
        refreshNotifier: _albumRefreshNotifier,
        onOpenSettings: _openSettings,
      ), // Albums is now second
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getAppBarTitle(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (_activeAccountName != null)
              Text(
                _activeAccountName!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          // Account switcher button
          if (_activeAccountName != null)
            PopupMenuButton<String>(
              icon: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.blue.shade100,
                child: Icon(
                  Icons.account_circle,
                  size: 20,
                  color: Colors.blue.shade700,
                ),
              ),
              tooltip: 'Switch Account',
              onSelected: (value) {
                if (value == 'manage') {
                  _openAccountManagement();
                } else if (value == 'settings') {
                  _openSettings();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'manage',
                  child: Row(
                    children: [
                      const Icon(Icons.manage_accounts),
                      const SizedBox(width: 8),
                      Text('Account: $_activeAccountName'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings),
                      SizedBox(width: 8),
                      Text('Settings'),
                    ],
                  ),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: _openAccountManagement,
              tooltip: 'Add Account',
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
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
