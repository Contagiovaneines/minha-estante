class LocalFolderSource {
  final String id;
  final String userId;
  final String name;
  final String path;
  final int itemCount;
  final DateTime? lastSyncedAt;
  final DateTime createdAt;

  const LocalFolderSource({
    required this.id,
    required this.userId,
    required this.name,
    required this.path,
    this.itemCount = 0,
    this.lastSyncedAt,
    required this.createdAt,
  });

  LocalFolderSource copyWith({
    String? id,
    String? userId,
    String? name,
    String? path,
    int? itemCount,
    DateTime? lastSyncedAt,
    DateTime? createdAt,
  }) {
    return LocalFolderSource(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      path: path ?? this.path,
      itemCount: itemCount ?? this.itemCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'name': name,
    'path': path,
    'itemCount': itemCount,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory LocalFolderSource.fromJson(Map<String, dynamic> json) =>
      LocalFolderSource(
        id: json['id'] as String,
        userId: json['userId'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
        itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
        lastSyncedAt: json['lastSyncedAt'] != null
            ? DateTime.parse(json['lastSyncedAt'] as String)
            : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class LocalFolderSyncResult {
  final int added;
  final int total;
  final int duplicates;
  final List<String> duplicateTitles;
  final List<String> errors;
  final int pdfAdded;
  final int cbzAdded;
  final int cbrConverted;
  final int cbrFailed;
  final int ignored;

  const LocalFolderSyncResult({
    required this.added,
    required this.total,
    this.duplicates = 0,
    this.duplicateTitles = const [],
    this.errors = const [],
    this.pdfAdded = 0,
    this.cbzAdded = 0,
    this.cbrConverted = 0,
    this.cbrFailed = 0,
    this.ignored = 0,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get hasDuplicates => duplicates > 0;
}
