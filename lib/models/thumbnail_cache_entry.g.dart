// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thumbnail_cache_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ThumbnailCacheEntryAdapter extends TypeAdapter<ThumbnailCacheEntry> {
  @override
  final int typeId = 0;

  @override
  ThumbnailCacheEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ThumbnailCacheEntry(
      url: fields[0] as String,
      imageData: fields[1] as Uint8List,
      cachedAt: fields[2] as DateTime,
      lastAccessedAt: fields[3] as DateTime,
      accessCount: fields[4] as int,
      assetModifiedAt: fields[5] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ThumbnailCacheEntry obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.url)
      ..writeByte(1)
      ..write(obj.imageData)
      ..writeByte(2)
      ..write(obj.cachedAt)
      ..writeByte(3)
      ..write(obj.lastAccessedAt)
      ..writeByte(4)
      ..write(obj.accessCount)
      ..writeByte(5)
      ..write(obj.assetModifiedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThumbnailCacheEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
