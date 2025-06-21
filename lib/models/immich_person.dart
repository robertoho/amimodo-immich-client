class ImmichPerson {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final int faceCount;

  ImmichPerson({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    required this.faceCount,
  });

  factory ImmichPerson.fromJson(Map<String, dynamic> json) {
    return ImmichPerson(
      id: json['id'],
      name: json['name'],
      thumbnailUrl: json['thumbnailPath'],
      faceCount: json['faceCount'] ?? 0,
    );
  }
}
