import 'package:uuid/uuid.dart';

/// Representa um marcador (bookmark) salvo pelo usuário em um item da biblioteca.
class Bookmark {
  final String id;
  final String itemId;
  final String userId;

  /// Número da página (para PDF). Null para EPUB.
  final int? page;

  /// CFI (Canonical Fragment Identifier) para EPUB. Null para PDF.
  final String? cfi;

  /// Etiqueta descritiva do marcador.
  final String label;

  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.itemId,
    required this.userId,
    this.page,
    this.cfi,
    required this.label,
    required this.createdAt,
  });

  factory Bookmark.createPdf({
    required String itemId,
    required String userId,
    required int page,
    String? label,
  }) {
    return Bookmark(
      id: const Uuid().v4(),
      itemId: itemId,
      userId: userId,
      page: page,
      label: label ?? 'Página $page',
      createdAt: DateTime.now(),
    );
  }

  factory Bookmark.createEpub({
    required String itemId,
    required String userId,
    required String cfi,
    String? label,
  }) {
    return Bookmark(
      id: const Uuid().v4(),
      itemId: itemId,
      userId: userId,
      cfi: cfi,
      label: label ?? 'Trecho marcado',
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'itemId': itemId,
    'userId': userId,
    'page': page,
    'cfi': cfi,
    'label': label,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String,
    itemId: json['itemId'] as String,
    userId: json['userId'] as String,
    page: json['page'] as int?,
    cfi: json['cfi'] as String?,
    label: json['label'] as String? ?? 'Marcador',
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
