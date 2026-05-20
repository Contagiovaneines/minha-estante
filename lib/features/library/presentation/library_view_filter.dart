import '../domain/library_item.dart';

enum LibraryViewFilter { all, newItems, favorites, reading, finished, toRead }

enum LibraryTypeFilter { all, pdf, hq, audio, ebook, document }

extension LibraryViewFilterLabel on LibraryViewFilter {
  String get label {
    switch (this) {
      case LibraryViewFilter.all:
        return 'Todos';
      case LibraryViewFilter.newItems:
        return 'Novos';
      case LibraryViewFilter.favorites:
        return 'Favoritos';
      case LibraryViewFilter.reading:
        return 'Lendo';
      case LibraryViewFilter.finished:
        return 'Lidos';
      case LibraryViewFilter.toRead:
        return 'Para ler';
    }
  }

  bool matches(LibraryItem item) {
    switch (this) {
      case LibraryViewFilter.all:
        return true;
      case LibraryViewFilter.newItems:
        return item.isNew;
      case LibraryViewFilter.favorites:
        return item.isFavorite;
      case LibraryViewFilter.reading:
        return item.status == LibraryItemStatus.reading;
      case LibraryViewFilter.finished:
        return item.status == LibraryItemStatus.finished;
      case LibraryViewFilter.toRead:
        return item.status == LibraryItemStatus.toRead;
    }
  }
}

extension LibraryTypeFilterLabel on LibraryTypeFilter {
  String get label {
    switch (this) {
      case LibraryTypeFilter.all:
        return 'Tudo';
      case LibraryTypeFilter.pdf:
        return 'PDF';
      case LibraryTypeFilter.hq:
        return 'HQ';
      case LibraryTypeFilter.audio:
        return 'Áudio';
      case LibraryTypeFilter.ebook:
        return 'Ebook';
      case LibraryTypeFilter.document:
        return 'Documento';
    }
  }

  bool matchesType(LibraryItem item) {
    switch (this) {
      case LibraryTypeFilter.all:
        return true;
      case LibraryTypeFilter.pdf:
        return item.type == ItemType.pdf;
      case LibraryTypeFilter.hq:
        return item.type == ItemType.hq;
      case LibraryTypeFilter.audio:
        return item.type == ItemType.audio;
      case LibraryTypeFilter.ebook:
        return item.type == ItemType.ebook;
      case LibraryTypeFilter.document:
        return item.type == ItemType.document || item.type == ItemType.text;
    }
  }
}

bool itemMatchesSearch(
  LibraryItem item,
  String query, {
  String authorQuery = '',
  String collectionQuery = '',
}) {
  final parsed = _ParsedLibrarySearch.parse(query);

  if (!_allTermsMatch(authorQuery, [item.author])) return false;
  if (!_allTermsMatch(collectionQuery, [
    item.collectionName,
    item.relativePath,
  ])) {
    return false;
  }

  if (parsed.author != null && !_allTermsMatch(parsed.author!, [item.author])) {
    return false;
  }
  if (parsed.collection != null &&
      !_allTermsMatch(parsed.collection!, [
        item.collectionName,
        item.relativePath,
      ])) {
    return false;
  }
  if (parsed.type != null && !parsed.type!.matchesType(item)) {
    return false;
  }

  return _allTermsMatch(parsed.freeText, [
    item.title,
    item.author,
    item.collectionName,
    item.relativePath,
    item.type.name,
  ]);
}

bool _allTermsMatch(String query, List<String?> fields) {
  final terms = _normalize(
    query,
  ).split(RegExp(r'\s+')).where((term) => term.isNotEmpty).toList();
  if (terms.isEmpty) return true;

  final normalizedFields = fields.map(_normalize).toList();
  return terms.every(
    (term) => normalizedFields.any((field) => field.contains(term)),
  );
}

String _normalize(String? value) {
  return (value ?? '')
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c')
      .trim();
}

class _ParsedLibrarySearch {
  final String freeText;
  final String? author;
  final String? collection;
  final LibraryTypeFilter? type;

  const _ParsedLibrarySearch({
    required this.freeText,
    this.author,
    this.collection,
    this.type,
  });

  factory _ParsedLibrarySearch.parse(String query) {
    final values = <String, String>{};
    final pattern = RegExp(
      r'(autor|author|colecao|coleção|estante|collection|tipo|type):(?:"([^"]+)"|(\S+))',
      caseSensitive: false,
    );
    final freeText = query.replaceAllMapped(pattern, (match) {
      final key = _normalize(match.group(1));
      final value = (match.group(2) ?? match.group(3) ?? '').trim();
      if (value.isNotEmpty) values[key] = value;
      return ' ';
    });

    final author = values['autor'] ?? values['author'];
    final collection =
        values['colecao'] ?? values['estante'] ?? values['collection'];
    final typeValue = values['tipo'] ?? values['type'];

    return _ParsedLibrarySearch(
      freeText: freeText,
      author: author,
      collection: collection,
      type: typeValue == null ? null : _typeFromSearch(typeValue),
    );
  }
}

LibraryTypeFilter? _typeFromSearch(String value) {
  final normalized = _normalize(value);
  switch (normalized) {
    case 'pdf':
      return LibraryTypeFilter.pdf;
    case 'hq':
    case 'comic':
    case 'quadrinho':
      return LibraryTypeFilter.hq;
    case 'audio':
    case 'audiobook':
      return LibraryTypeFilter.audio;
    case 'ebook':
    case 'epub':
    case 'livro':
      return LibraryTypeFilter.ebook;
    case 'doc':
    case 'documento':
    case 'text':
    case 'texto':
      return LibraryTypeFilter.document;
    default:
      return null;
  }
}
