class ReadingProgress {
  final String id;
  final String userId;
  final String itemId;
  final int currentPage;
  final int totalPages;
  final double percent;
  final int? positionSeconds;
  final DateTime updatedAt;

  const ReadingProgress({
    required this.id,
    required this.userId,
    required this.itemId,
    required this.currentPage,
    required this.totalPages,
    required this.percent,
    this.positionSeconds,
    required this.updatedAt,
  });

  ReadingProgress copyWith({
    String? id,
    String? userId,
    String? itemId,
    int? currentPage,
    int? totalPages,
    double? percent,
    int? positionSeconds,
    DateTime? updatedAt,
  }) {
    return ReadingProgress(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      itemId: itemId ?? this.itemId,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      percent: percent ?? this.percent,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'itemId': itemId,
    'currentPage': currentPage,
    'totalPages': totalPages,
    'percent': percent,
    'positionSeconds': positionSeconds,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ReadingProgress.fromJson(Map<String, dynamic> json) =>
      ReadingProgress(
        id: json['id'] as String,
        userId: json['userId'] as String,
        itemId: json['itemId'] as String,
        currentPage: (json['currentPage'] as num).toInt(),
        totalPages: (json['totalPages'] as num).toInt(),
        percent: (json['percent'] as num).toDouble(),
        positionSeconds: (json['positionSeconds'] as num?)?.toInt(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
