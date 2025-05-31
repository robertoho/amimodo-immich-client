class ImmichAlbum {
  final String id;
  final String albumName;
  final String? albumThumbnailAssetId;
  final int assetCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? description;
  final bool shared;
  final bool hasSharedLink;
  final String ownerId;
  final String? ownerName;
  final String? ownerEmail;

  ImmichAlbum({
    required this.id,
    required this.albumName,
    this.albumThumbnailAssetId,
    required this.assetCount,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.shared = false,
    this.hasSharedLink = false,
    required this.ownerId,
    this.ownerName,
    this.ownerEmail,
  });

  factory ImmichAlbum.fromJson(Map<String, dynamic> json) {
    return ImmichAlbum(
      id: json['id'] ?? '',
      albumName: json['albumName'] ?? 'Untitled Album',
      albumThumbnailAssetId: json['albumThumbnailAssetId'],
      assetCount: json['assetCount'] ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      description: json['description'],
      shared: json['shared'] ?? false,
      hasSharedLink: json['hasSharedLink'] ?? false,
      ownerId: json['ownerId'] ?? '',
      ownerName: json['owner']?['name'],
      ownerEmail: json['owner']?['email'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'albumName': albumName,
      'albumThumbnailAssetId': albumThumbnailAssetId,
      'assetCount': assetCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'description': description,
      'shared': shared,
      'hasSharedLink': hasSharedLink,
      'ownerId': ownerId,
    };
  }
}
