import 'package:hive/hive.dart';

part 'account.g.dart';

@HiveType(typeId: 1)
class Account extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String baseUrl;

  @HiveField(3)
  String apiKey;

  @HiveField(4)
  bool isActive;

  @HiveField(5)
  DateTime createdAt;

  @HiveField(6)
  DateTime lastUsed;

  Account({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    this.isActive = false,
    DateTime? createdAt,
    DateTime? lastUsed,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastUsed = lastUsed ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'lastUsed': lastUsed.toIso8601String(),
    };
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'],
      name: json['name'],
      baseUrl: json['baseUrl'],
      apiKey: json['apiKey'],
      isActive: json['isActive'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
      lastUsed: DateTime.parse(json['lastUsed']),
    );
  }

  Account copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastUsed,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  @override
  String toString() {
    return 'Account{id: $id, name: $name, baseUrl: $baseUrl, isActive: $isActive}';
  }
}
