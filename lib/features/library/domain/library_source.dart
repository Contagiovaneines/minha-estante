enum SourceType { folder, file }

class LibrarySource {
  final String id;
  final String userId;
  final String name;
  final String originalUrl;
  final String driveId;
  final SourceType sourceType;
  final int itemCount;
  final DateTime? lastSyncedAt;
  final DateTime createdAt;

  const LibrarySource({
    required this.id,
    required this.userId,
    required this.name,
    required this.originalUrl,
    required this.driveId,
    required this.sourceType,
    this.itemCount = 0,
    this.lastSyncedAt,
    required this.createdAt,
  });

  LibrarySource copyWith({
    String? id,
    String? userId,
    String? name,
    String? originalUrl,
    String? driveId,
    SourceType? sourceType,
    int? itemCount,
    DateTime? lastSyncedAt,
    DateTime? createdAt,
  }) {
    return LibrarySource(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      originalUrl: originalUrl ?? this.originalUrl,
      driveId: driveId ?? this.driveId,
      sourceType: sourceType ?? this.sourceType,
      itemCount: itemCount ?? this.itemCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'name': name,
    'originalUrl': originalUrl,
    'driveId': driveId,
    'sourceType': sourceType.name,
    'itemCount': itemCount,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory LibrarySource.fromJson(Map<String, dynamic> json) => LibrarySource(
    id: json['id'] as String,
    userId: json['userId'] as String,
    name: json['name'] as String,
    originalUrl: json['originalUrl'] as String,
    driveId: json['driveId'] as String,
    sourceType: SourceType.values.firstWhere(
      (e) => e.name == json['sourceType'],
    ),
    itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
    lastSyncedAt: json['lastSyncedAt'] != null
        ? DateTime.parse(json['lastSyncedAt'] as String)
        : null,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
