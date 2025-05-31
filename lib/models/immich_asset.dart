class ImmichAsset {
  final String id;
  final String type;
  final String originalPath;
  final String? thumbnailPath;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isFavorite;
  final String? description;

  ImmichAsset({
    required this.id,
    required this.type,
    required this.originalPath,
    this.thumbnailPath,
    required this.createdAt,
    required this.modifiedAt,
    this.isFavorite = false,
    this.description,
  });

  factory ImmichAsset.fromJson(Map<String, dynamic> json) {
    return ImmichAsset(
      id: json['id'] ?? '',
      type: json['type'] ?? 'IMAGE',
      originalPath: json['originalPath'] ?? '',
      thumbnailPath: json['thumbnailPath'],
      createdAt:
          DateTime.tryParse(json['fileCreatedAt'] ?? '') ?? DateTime.now(),
      modifiedAt:
          DateTime.tryParse(json['fileModifiedAt'] ?? '') ?? DateTime.now(),
      isFavorite: json['isFavorite'] ?? false,
      description: json['exifInfo']?['description'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'originalPath': originalPath,
      'thumbnailPath': thumbnailPath,
      'fileCreatedAt': createdAt.toIso8601String(),
      'fileModifiedAt': modifiedAt.toIso8601String(),
      'isFavorite': isFavorite,
      'description': description,
    };
  }
}
