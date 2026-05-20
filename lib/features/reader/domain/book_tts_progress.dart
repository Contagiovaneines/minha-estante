class BookTtsProgress {
  final String itemId;
  final int segmentIndex;
  final int totalSegments;
  final double percent;
  final String language;
  final String? voiceName;
  final String? voiceLocale;
  final double speechRate;
  final DateTime updatedAt;

  const BookTtsProgress({
    required this.itemId,
    required this.segmentIndex,
    required this.totalSegments,
    required this.percent,
    required this.language,
    this.voiceName,
    this.voiceLocale,
    required this.speechRate,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'segmentIndex': segmentIndex,
    'totalSegments': totalSegments,
    'percent': percent,
    'language': language,
    'voiceName': voiceName,
    'voiceLocale': voiceLocale,
    'speechRate': speechRate,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory BookTtsProgress.fromJson(Map<String, dynamic> json) {
    return BookTtsProgress(
      itemId: json['itemId'] as String,
      segmentIndex: (json['segmentIndex'] as num?)?.toInt() ?? 0,
      totalSegments: (json['totalSegments'] as num?)?.toInt() ?? 0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
      language: json['language'] as String? ?? 'pt-BR',
      voiceName: json['voiceName'] as String?,
      voiceLocale: json['voiceLocale'] as String?,
      speechRate: (json['speechRate'] as num?)?.toDouble() ?? 0.45,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
