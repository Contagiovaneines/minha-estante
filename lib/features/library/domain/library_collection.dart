import 'library_item.dart';

class LibraryCollection {
  final String id;
  final String name;
  final ItemOrigin origin;
  final int itemCount;
  final int newCount;
  final LibraryItem coverItem;
  final DateTime updatedAt;

  const LibraryCollection({
    required this.id,
    required this.name,
    required this.origin,
    required this.itemCount,
    required this.newCount,
    required this.coverItem,
    required this.updatedAt,
  });

  static List<LibraryCollection> fromItems(List<LibraryItem> items) {
    final grouped = <String, List<LibraryItem>>{};
    for (final item in items) {
      final id = item.collectionId ?? 'collection_${item.origin.name}_default';
      grouped.putIfAbsent(id, () => []).add(item);
    }

    final collections =
        grouped.entries.map((entry) {
          final collectionItems = [...entry.value]
            ..sort((a, b) {
              if (a.isNew != b.isNew) return a.isNew ? -1 : 1;
              return b.updatedAt.compareTo(a.updatedAt);
            });
          final cover = collectionItems.first;
          return LibraryCollection(
            id: entry.key,
            name:
                cover.collectionName ??
                (cover.origin == ItemOrigin.local
                    ? 'Arquivos manuais'
                    : 'Online'),
            origin: cover.origin,
            itemCount: collectionItems.length,
            newCount: collectionItems.where((item) => item.isNew).length,
            coverItem: cover,
            updatedAt: cover.updatedAt,
          );
        }).toList()..sort((a, b) {
          if (a.newCount != b.newCount) return b.newCount.compareTo(a.newCount);
          return b.updatedAt.compareTo(a.updatedAt);
        });

    return collections;
  }
}
