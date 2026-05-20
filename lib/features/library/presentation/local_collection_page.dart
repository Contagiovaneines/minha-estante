import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../domain/library_item.dart';
import 'library_controller.dart';
import 'library_view_filter.dart';
import 'widgets/book_grid_card.dart';

class LocalCollectionPage extends ConsumerStatefulWidget {
  final String collectionId;

  const LocalCollectionPage({super.key, required this.collectionId});

  @override
  ConsumerState<LocalCollectionPage> createState() =>
      _LocalCollectionPageState();
}

class _LocalCollectionPageState extends ConsumerState<LocalCollectionPage> {
  final _searchController = TextEditingController();
  LibraryViewFilter _filter = LibraryViewFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryControllerProvider);

    return libraryState.when(
      loading: () => Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Erro: $error')),
      ),
      data: (items) {
        final allCollectionItems = items
            .where(
              (item) => _effectiveCollectionId(item) == widget.collectionId,
            )
            .toList();
        final collectionItems =
            allCollectionItems
                .where((item) => _filter.matches(item))
                .where(
                  (item) => itemMatchesSearch(item, _searchController.text),
                )
                .toList()
              ..sort(_sortByRelativePath);
        final title = allCollectionItems.isNotEmpty
            ? allCollectionItems.first.collectionName ?? 'Estante'
            : 'Estante';

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            ),
            title: Text(title),
          ),
          body: allCollectionItems.isEmpty
              ? const EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'Estante vazia',
                  subtitle: 'Os arquivos dessa estante nao foram encontrados.',
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: _buildSearchAndFilters(),
                    ),
                    Expanded(
                      child: collectionItems.isEmpty
                          ? const EmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'Nada encontrado',
                              subtitle:
                                  'Tente mudar a busca ou o filtro selecionado.',
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                32,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    childAspectRatio: 0.62,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                              itemCount: collectionItems.length,
                              itemBuilder: (context, index) {
                                final item = collectionItems[index];
                                return BookGridCard(
                                  item: item,
                                  onTap: () => context.push('/book/${item.id}'),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildSearchAndFilters() {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Buscar nesta estante',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Limpar busca',
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: LibraryViewFilter.values.length,
            separatorBuilder: (_, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final filter = LibraryViewFilter.values[index];
              final selected = filter == _filter;
              return ChoiceChip(
                label: Text(filter.label),
                selected: selected,
                onSelected: (_) => setState(() => _filter = filter),
                labelStyle: TextStyle(
                  color: selected ? colors.onPrimary : colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                selectedColor: colors.primary,
                backgroundColor: colors.surface,
                side: BorderSide(
                  color: selected ? colors.primary : colors.outline,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static int _sortByRelativePath(LibraryItem a, LibraryItem b) {
    if (a.isNew != b.isNew) return a.isNew ? -1 : 1;
    final aPath = a.relativePath ?? a.title;
    final bPath = b.relativePath ?? b.title;
    return aPath.toLowerCase().compareTo(bPath.toLowerCase());
  }

  static String _effectiveCollectionId(LibraryItem item) {
    return item.collectionId ?? 'collection_${item.origin.name}_default';
  }
}
