import 'package:flutter/foundation.dart';
import '../models/immich_asset.dart';
import '../services/immich_api_service.dart';

class VirtualizedPhotoService extends ChangeNotifier {
  final ImmichApiService _apiService;

  // Configuration
  static const int _pageSize = 100; // Items per page
  static const int _bufferPages = 2; // Pages to load before/after visible area
  static const int _cacheSize = 1000; // Maximum items to keep in memory

  // State
  final Map<int, ImmichAsset> _loadedAssets = {};
  final Set<int> _loadingPages = {};
  final Set<int> _loadedPages = {};
  int _totalCount = 0;
  bool _isInitialized = false;
  String? _lastError;

  VirtualizedPhotoService(this._apiService);

  // Getters
  int get totalCount => _totalCount;
  bool get isInitialized => _isInitialized;
  String? get lastError => _lastError;
  int get loadedAssetsCount => _loadedAssets.length;

  // Initialize and get total count
  Future<void> initialize() async {
    if (!_apiService.isConfigured) {
      _lastError = 'API service not configured';
      notifyListeners();
      return;
    }

    try {
      // Get first page to determine total count - using searchAssets instead of searchMetadata
      final searchResult = await _apiService.searchAssets(
        page: 1,
        size: _pageSize,
        order: 'desc',
      );

      List<dynamic> jsonList;
      if (searchResult['assets'] is List) {
        jsonList = searchResult['assets'] ?? [];
      } else if (searchResult['assets'] is Map) {
        final assetsMap = searchResult['assets'] as Map<String, dynamic>;
        jsonList = assetsMap['items'] ?? [];
      } else {
        jsonList = [];
      }

      final assets =
          jsonList.map((json) => ImmichAsset.fromJson(json)).toList();

      // Store first page
      for (int i = 0; i < assets.length; i++) {
        _loadedAssets[i] = assets[i];
      }
      _loadedPages.add(1);

      // For now, estimate total count based on first page
      // In a real implementation, you'd get this from the API
      _totalCount = assets.length < _pageSize
          ? assets.length
          : assets.length * 200; // Estimate

      _isInitialized = true;
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  // Get asset at specific index (loads page if needed)
  ImmichAsset? getAsset(int index) {
    if (index < 0 || index >= _totalCount) return null;

    // Check if asset is already loaded
    if (_loadedAssets.containsKey(index)) {
      return _loadedAssets[index];
    }

    // Trigger page load if not already loading
    final pageNumber = (index ~/ _pageSize) + 1;
    if (!_loadedPages.contains(pageNumber) &&
        !_loadingPages.contains(pageNumber)) {
      _loadPage(pageNumber);
    }

    return null; // Return null while loading
  }

  // Load pages for visible range
  Future<void> loadVisibleRange(int startIndex, int endIndex) async {
    final startPage = (startIndex ~/ _pageSize) + 1;
    final endPage = (endIndex ~/ _pageSize) + 1;

    // Load pages for visible range plus buffer
    final loadStartPage =
        (startPage - _bufferPages).clamp(1, double.infinity).toInt();
    final loadEndPage = endPage + _bufferPages;

    final pagesToLoad = <int>[];
    for (int page = loadStartPage; page <= loadEndPage; page++) {
      if (!_loadedPages.contains(page) && !_loadingPages.contains(page)) {
        pagesToLoad.add(page);
      }
    }

    // Load pages concurrently
    final futures = pagesToLoad.map(_loadPage);
    await Future.wait(futures);

    // Clean up distant pages to manage memory
    _cleanupDistantPages(loadStartPage, loadEndPage);
  }

  // Load a specific page
  Future<void> _loadPage(int pageNumber) async {
    if (_loadingPages.contains(pageNumber) ||
        _loadedPages.contains(pageNumber)) {
      return;
    }

    _loadingPages.add(pageNumber);

    try {
      final searchResult = await _apiService.searchAssets(
        page: pageNumber,
        size: _pageSize,
        order: 'desc',
      );

      List<dynamic> jsonList;
      if (searchResult['assets'] is List) {
        jsonList = searchResult['assets'] ?? [];
      } else if (searchResult['assets'] is Map) {
        final assetsMap = searchResult['assets'] as Map<String, dynamic>;
        jsonList = assetsMap['items'] ?? [];
      } else {
        jsonList = [];
      }

      final assets =
          jsonList.map((json) => ImmichAsset.fromJson(json)).toList();

      // Store assets with their global indices
      final startIndex = (pageNumber - 1) * _pageSize;
      for (int i = 0; i < assets.length; i++) {
        _loadedAssets[startIndex + i] = assets[i];
      }

      _loadedPages.add(pageNumber);
      _loadingPages.remove(pageNumber);

      // Update total count if we got less than expected (reached end)
      if (assets.length < _pageSize && pageNumber > 1) {
        _totalCount = startIndex + assets.length;
      }

      notifyListeners();
    } catch (e) {
      _loadingPages.remove(pageNumber);
      _lastError = e.toString();
      notifyListeners();
    }
  }

  // Clean up pages that are far from visible area
  void _cleanupDistantPages(int keepStartPage, int keepEndPage) {
    if (_loadedAssets.length <= _cacheSize) return;

    final pagesToRemove = <int>[];
    for (final page in _loadedPages) {
      if (page < keepStartPage - _bufferPages ||
          page > keepEndPage + _bufferPages) {
        pagesToRemove.add(page);
      }
    }

    for (final page in pagesToRemove) {
      final startIndex = (page - 1) * _pageSize;
      final endIndex = startIndex + _pageSize;

      for (int i = startIndex; i < endIndex; i++) {
        _loadedAssets.remove(i);
      }
      _loadedPages.remove(page);
    }

    if (pagesToRemove.isNotEmpty) {
      debugPrint('🧹 Cleaned up ${pagesToRemove.length} pages from memory');
    }
  }

  // Refresh all data
  Future<void> refresh() async {
    _loadedAssets.clear();
    _loadedPages.clear();
    _loadingPages.clear();
    _isInitialized = false;
    _totalCount = 0;
    _lastError = null;

    await initialize();
  }

  // Check if an index is loading
  bool isLoading(int index) {
    final pageNumber = (index ~/ _pageSize) + 1;
    return _loadingPages.contains(pageNumber);
  }
}
