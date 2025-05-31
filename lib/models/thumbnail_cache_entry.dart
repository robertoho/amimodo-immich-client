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

  ThumbnailCacheEntry({
    required this.url,
    required this.imageData,
    required this.cachedAt,
    required this.lastAccessedAt,
    this.accessCount = 1,
  });

  // Update access tracking
  void markAccessed() {
    lastAccessedAt = DateTime.now();
    accessCount++;
    // Note: Don't auto-save here as the object might not be attached to box
    // The service will handle saving when needed
  }

  // Check if cache entry is expired
  bool isExpired(Duration expiry) {
    return DateTime.now().difference(cachedAt) > expiry;
  }

  // Get cache entry size in bytes
  int get sizeInBytes => imageData.length;
}
