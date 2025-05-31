import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/thumbnail_cache_entry.dart';

class ThumbnailCacheService {
  static final ThumbnailCacheService _instance =
      ThumbnailCacheService._internal();
  factory ThumbnailCacheService() => _instance;
  ThumbnailCacheService._internal();

  static const String _boxName = 'thumbnailCache';
  static const int _maxCacheSize = 500 * 1024 * 1024; // 500MB max cache size
  static const int _maxCacheEntries =
      10000; // Maximum number of cached thumbnails
  static const Duration _cacheExpiry = Duration(days: 30); // Cache expiry time

  Box<ThumbnailCacheEntry>? _cacheBox;
  final Map<String, ThumbnailCacheEntry> _memoryCache =
      {}; // Hot cache for recent items

  Future<void> initialize() async {
    try {
      _cacheBox = await Hive.openBox<ThumbnailCacheEntry>(_boxName);

      // Clean up expired entries on startup
      await _cleanupExpiredEntries();

      debugPrint(
          '📁 Thumbnail cache initialized with ${_cacheBox!.length} entries');
    } catch (e) {
      debugPrint('❌ Error initializing thumbnail cache: $e');
    }
  }

  // Generate cache key from URL
  String _getCacheKey(String url) {
    final bytes = utf8.encode(url);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  // Check if thumbnail is cached
  Future<bool> isCached(String url) async {
    if (_cacheBox == null) {
      await initialize();
      if (_cacheBox == null) return false;
    }

    final cacheKey = _getCacheKey(url);

    // Check memory cache first
    if (_memoryCache.containsKey(cacheKey)) {
      final entry = _memoryCache[cacheKey]!;
      if (!entry.isExpired(_cacheExpiry)) {
        return true;
      } else {
        _memoryCache.remove(cacheKey);
      }
    }

    // Check Hive cache
    final entry = _cacheBox!.get(cacheKey);
    if (entry != null && !entry.isExpired(_cacheExpiry)) {
      // Add to memory cache for faster access
      _memoryCache[cacheKey] = entry;
      return true;
    }

    return false;
  }

  // Get cached thumbnail
  Future<Uint8List?> getCachedThumbnail(String url) async {
    if (_cacheBox == null) {
      await initialize();
      if (_cacheBox == null) return null;
    }

    final cacheKey = _getCacheKey(url);

    // Check memory cache first
    if (_memoryCache.containsKey(cacheKey)) {
      final entry = _memoryCache[cacheKey]!;
      if (!entry.isExpired(_cacheExpiry)) {
        entry.markAccessed();
        // Save the updated access info back to Hive
        await _cacheBox!.put(cacheKey, entry);
        return entry.imageData;
      } else {
        _memoryCache.remove(cacheKey);
        await _cacheBox!.delete(cacheKey);
      }
    }

    // Check Hive cache
    final entry = _cacheBox!.get(cacheKey);
    if (entry != null) {
      if (!entry.isExpired(_cacheExpiry)) {
        // Add to memory cache and mark as accessed
        _memoryCache[cacheKey] = entry;
        entry.markAccessed();
        // Save the updated access info back to Hive
        await _cacheBox!.put(cacheKey, entry);
        return entry.imageData;
      } else {
        // Entry is expired, remove it
        await _cacheBox!.delete(cacheKey);
      }
    }

    return null;
  }

  // Download and cache thumbnail
  Future<Uint8List?> downloadAndCacheThumbnail(
      String url, Map<String, String>? headers) async {
    if (_cacheBox == null) {
      await initialize();
      if (_cacheBox == null) return null;
    }

    try {
      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        await _cacheThumbnail(url, bytes);
        return bytes;
      } else {
        debugPrint('❌ Failed to download thumbnail: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error downloading thumbnail: $e');
      return null;
    }
  }

  // Cache thumbnail data
  Future<void> _cacheThumbnail(String url, Uint8List bytes) async {
    if (_cacheBox == null) return;

    final cacheKey = _getCacheKey(url);
    final now = DateTime.now();

    try {
      final entry = ThumbnailCacheEntry(
        url: url,
        imageData: bytes,
        cachedAt: now,
        lastAccessedAt: now,
        accessCount: 1,
      );

      await _cacheBox!.put(cacheKey, entry);
      _memoryCache[cacheKey] = entry;

      // Check if we need to cleanup cache
      await _checkCacheSize();
    } catch (e) {
      debugPrint('❌ Error caching thumbnail: $e');
    }
  }

  // Clean up expired entries
  Future<void> _cleanupExpiredEntries() async {
    if (_cacheBox == null) return;

    try {
      final keysToDelete = <String>[];
      final now = DateTime.now();

      for (final key in _cacheBox!.keys) {
        final entry = _cacheBox!.get(key);
        if (entry != null && entry.isExpired(_cacheExpiry)) {
          keysToDelete.add(key);
        }
      }

      if (keysToDelete.isNotEmpty) {
        await _cacheBox!.deleteAll(keysToDelete);

        // Also remove from memory cache
        for (final key in keysToDelete) {
          _memoryCache.remove(key);
        }

        debugPrint(
            '🧹 Cleaned up ${keysToDelete.length} expired cached thumbnails');
      }
    } catch (e) {
      debugPrint('❌ Error cleaning up expired entries: $e');
    }
  }

  // Check cache size and cleanup if necessary
  Future<void> _checkCacheSize() async {
    if (_cacheBox == null) return;

    try {
      final entries = _cacheBox!.values.toList();

      // Calculate total size
      int totalSize = 0;
      for (final entry in entries) {
        totalSize += entry.sizeInBytes;
      }

      // Check size and entry count limits
      if (entries.length > _maxCacheEntries || totalSize > _maxCacheSize) {
        await _performLRUCleanup(entries);
      }
    } catch (e) {
      debugPrint('❌ Error checking cache size: $e');
    }
  }

  // Perform LRU cleanup based on access patterns
  Future<void> _performLRUCleanup(List<ThumbnailCacheEntry> entries) async {
    try {
      // Sort by last accessed time (oldest first) and access count (least used first)
      entries.sort((a, b) {
        // Primary sort by last accessed time
        final timeDiff = a.lastAccessedAt.compareTo(b.lastAccessedAt);
        if (timeDiff != 0) return timeDiff;

        // Secondary sort by access count
        return a.accessCount.compareTo(b.accessCount);
      });

      // Delete oldest 25% of entries
      final entriesToDelete = (entries.length * 0.25).round();
      final keysToDelete = <String>[];

      for (int i = 0; i < entriesToDelete && i < entries.length; i++) {
        final entry = entries[i];
        final cacheKey = _getCacheKey(entry.url);
        keysToDelete.add(cacheKey);
      }

      if (keysToDelete.isNotEmpty) {
        await _cacheBox!.deleteAll(keysToDelete);

        // Also remove from memory cache
        for (final key in keysToDelete) {
          _memoryCache.remove(key);
        }

        debugPrint(
            '🧹 LRU cleanup: deleted ${keysToDelete.length} cached thumbnails');
      }
    } catch (e) {
      debugPrint('❌ Error performing LRU cleanup: $e');
    }
  }

  // Get cache statistics
  Future<Map<String, dynamic>> getCacheStats() async {
    if (_cacheBox == null) return {'error': 'Cache not initialized'};

    try {
      final entries = _cacheBox!.values.toList();

      int totalSize = 0;
      int totalAccessCount = 0;
      DateTime? oldestEntry;
      DateTime? newestEntry;

      for (final entry in entries) {
        totalSize += entry.sizeInBytes;
        totalAccessCount += entry.accessCount;

        if (oldestEntry == null || entry.cachedAt.isBefore(oldestEntry)) {
          oldestEntry = entry.cachedAt;
        }

        if (newestEntry == null || entry.cachedAt.isAfter(newestEntry)) {
          newestEntry = entry.cachedAt;
        }
      }

      return {
        'total_entries': entries.length,
        'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'memory_cache_size': _memoryCache.length,
        'average_access_count': entries.isNotEmpty
            ? (totalAccessCount / entries.length).toStringAsFixed(1)
            : '0',
        'oldest_entry': oldestEntry?.toIso8601String(),
        'newest_entry': newestEntry?.toIso8601String(),
        'box_name': _boxName,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // Clear all cache
  Future<void> clearCache() async {
    if (_cacheBox == null) return;

    try {
      await _cacheBox!.clear();
      _memoryCache.clear();

      debugPrint('🧹 Thumbnail cache cleared');
    } catch (e) {
      debugPrint('❌ Error clearing cache: $e');
    }
  }

  // Preload thumbnails for a list of URLs
  Future<void> preloadThumbnails(
      List<String> urls, Map<String, String>? headers) async {
    final futures = <Future>[];

    for (final url in urls) {
      if (!await isCached(url)) {
        futures.add(downloadAndCacheThumbnail(url, headers));
      }

      // Limit concurrent downloads to avoid overwhelming the system
      if (futures.length >= 5) {
        await Future.wait(futures);
        futures.clear();
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  // Get most accessed thumbnails
  Future<List<String>> getMostAccessedUrls({int limit = 10}) async {
    if (_cacheBox == null) return [];

    try {
      final entries = _cacheBox!.values.toList();
      entries.sort((a, b) => b.accessCount.compareTo(a.accessCount));

      return entries.take(limit).map((entry) => entry.url).toList();
    } catch (e) {
      debugPrint('❌ Error getting most accessed URLs: $e');
      return [];
    }
  }

  // Test method to verify Hive is working
  Future<bool> testHiveConnection() async {
    if (_cacheBox == null) {
      await initialize();
    }

    try {
      // Test basic Hive functionality
      final testKey = 'test_key';
      final testEntry = ThumbnailCacheEntry(
        url: 'test_url',
        imageData: Uint8List.fromList([1, 2, 3, 4]),
        cachedAt: DateTime.now(),
        lastAccessedAt: DateTime.now(),
      );

      // Write test data
      await _cacheBox!.put(testKey, testEntry);

      // Read test data
      final retrievedEntry = _cacheBox!.get(testKey);

      // Clean up test data
      await _cacheBox!.delete(testKey);

      return retrievedEntry != null && retrievedEntry.url == 'test_url';
    } catch (e) {
      debugPrint('❌ Hive test failed: $e');
      return false;
    }
  }
}
