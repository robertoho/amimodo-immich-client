import 'package:hive/hive.dart';
import 'dart:typed_data';

part 'thumbnail_cache_entry.g.dart';

@HiveType(typeId: 0)
class ThumbnailCacheEntry extends HiveObject {
  @HiveField(0)
  late String url;

  @HiveField(1)
  late Uint8List imageData;

  @HiveField(2)
  late DateTime cachedAt;

  @HiveField(3)
  late DateTime lastAccessedAt;

  @HiveField(4)
  late int accessCount;

  @HiveField(5)
  late DateTime? assetModifiedAt;

  ThumbnailCacheEntry({
    required this.url,
    required this.imageData,
    required this.cachedAt,
    required this.lastAccessedAt,
    this.accessCount = 1,
    this.assetModifiedAt,
  });

  // Method to check if cache entry is expired
  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(cachedAt) > maxAge;
  }

  // Mark as accessed to support LRU
  void markAccessed() {
    lastAccessedAt = DateTime.now();
    accessCount++;
  }

  // Get size of entry in bytes
  int get sizeInBytes => imageData.lengthInBytes;

  @override
  String toString() {
    return 'ThumbnailCacheEntry(url: $url, cachedAt: $cachedAt, lastAccessed: $lastAccessedAt, accessCount: $accessCount, size: $sizeInBytes, assetModifiedAt: $assetModifiedAt)';
  }
}
