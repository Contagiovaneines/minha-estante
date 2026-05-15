import '../domain/library_item.dart';

enum LibraryViewFilter { all, newItems, favorites, reading, finished, toRead }

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

bool itemMatchesSearch(LibraryItem item, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;

  return item.title.toLowerCase().contains(normalized) ||
      (item.author ?? '').toLowerCase().contains(normalized) ||
      (item.collectionName ?? '').toLowerCase().contains(normalized) ||
      (item.relativePath ?? '').toLowerCase().contains(normalized);
}
