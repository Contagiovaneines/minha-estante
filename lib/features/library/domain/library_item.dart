enum ItemType { pdf, hq, audio, ebook, document, text }

enum ItemOrigin { online, local }

enum LibraryItemStatus { toRead, reading, finished }

class LibraryItem {
  final String id;
  final String userId;
  final String? sourceId;
  final String title;
  final String? author;
  final String? description;
  final String? collectionId;
  final String? collectionName;
  final String? relativePath;
  final ItemType type;
  final ItemOrigin origin;
  final String? driveFileId;
  final String? remoteUrl;
  final String? localPath;
  final String? thumbnailUrl;
  final int currentPage;
  final int totalPages;
  final double progress;
  final int? durationSeconds;
  final int? positionSeconds;
  final bool isNew;
  final bool isFavorite;
  final LibraryItemStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LibraryItem({
    required this.id,
    required this.userId,
    this.sourceId,
    required this.title,
    this.author,
    this.description,
    this.collectionId,
    this.collectionName,
    this.relativePath,
    required this.type,
    required this.origin,
    this.driveFileId,
    this.remoteUrl,
    this.localPath,
    this.thumbnailUrl,
    this.currentPage = 0,
    this.totalPages = 0,
    this.progress = 0.0,
    this.durationSeconds,
    this.positionSeconds,
    this.isNew = false,
    this.isFavorite = false,
    this.status = LibraryItemStatus.toRead,
    required this.createdAt,
    required this.updatedAt,
  });

  LibraryItem copyWith({
    String? id,
    String? userId,
    String? sourceId,
    String? title,
    String? author,
    String? description,
    String? collectionId,
    String? collectionName,
    String? relativePath,
    ItemType? type,
    ItemOrigin? origin,
    String? driveFileId,
    String? remoteUrl,
    String? localPath,
    String? thumbnailUrl,
    int? currentPage,
    int? totalPages,
    double? progress,
    int? durationSeconds,
    int? positionSeconds,
    bool? isNew,
    bool? isFavorite,
    LibraryItemStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LibraryItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      collectionId: collectionId ?? this.collectionId,
      collectionName: collectionName ?? this.collectionName,
      relativePath: relativePath ?? this.relativePath,
      type: type ?? this.type,
      origin: origin ?? this.origin,
      driveFileId: driveFileId ?? this.driveFileId,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      localPath: localPath ?? this.localPath,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      progress: progress ?? this.progress,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      isNew: isNew ?? this.isNew,
      isFavorite: isFavorite ?? this.isFavorite,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'sourceId': sourceId,
    'title': title,
    'author': author,
    'description': description,
    'collectionId': collectionId,
    'collectionName': collectionName,
    'relativePath': relativePath,
    'type': type.name,
    'origin': origin.name,
    'driveFileId': driveFileId,
    'remoteUrl': remoteUrl,
    'localPath': localPath,
    'thumbnailUrl': thumbnailUrl,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'progress': progress,
    'durationSeconds': durationSeconds,
    'positionSeconds': positionSeconds,
    'isNew': isNew,
    'isFavorite': isFavorite,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory LibraryItem.fromJson(Map<String, dynamic> json) {
    final progress = (json['progress'] as num?)?.toDouble() ?? 0.0;
    return LibraryItem(
      id: json['id'] as String,
      userId: json['userId'] as String,
      sourceId: json['sourceId'] as String?,
      title: json['title'] as String,
      author: json['author'] as String?,
      description: json['description'] as String?,
      collectionId: json['collectionId'] as String?,
      collectionName: json['collectionName'] as String?,
      relativePath: json['relativePath'] as String?,
      type: ItemType.values.firstWhere((e) => e.name == json['type']),
      origin: ItemOrigin.values.firstWhere((e) => e.name == json['origin']),
      driveFileId: json['driveFileId'] as String?,
      remoteUrl: json['remoteUrl'] as String?,
      localPath: json['localPath'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      currentPage: (json['currentPage'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      progress: progress,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      positionSeconds: (json['positionSeconds'] as num?)?.toInt(),
      isNew: json['isNew'] as bool? ?? false,
      isFavorite: json['isFavorite'] as bool? ?? false,
      status: _statusFromJson(json['status'] as String?, progress),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static LibraryItemStatus _statusFromJson(String? value, double progress) {
    if (value != null) {
      return LibraryItemStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => _statusFromProgress(progress),
      );
    }
    return _statusFromProgress(progress);
  }

  static LibraryItemStatus _statusFromProgress(double progress) {
    if (progress >= 1.0) return LibraryItemStatus.finished;
    if (progress > 0) return LibraryItemStatus.reading;
    return LibraryItemStatus.toRead;
  }
}
