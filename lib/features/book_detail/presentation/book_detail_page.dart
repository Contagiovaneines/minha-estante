import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/progress_bar.dart';
import '../../library/domain/library_item.dart';
import '../../library/presentation/library_controller.dart';
import '../../library/presentation/widgets/library_item_cover.dart';
import '../../reader/domain/ebook_format_support.dart';

class BookDetailPage extends ConsumerWidget {
  final String itemId;

  const BookDetailPage({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryControllerProvider);

    return libraryState.when(
      loading: () =>
          const Scaffold(body: LoadingView(message: 'Carregando...')),
      error: (e, _) => Scaffold(body: Center(child: Text('Erro: $e'))),
      data: (items) {
        final item = items.cast<LibraryItem?>().firstWhere(
          (e) => e?.id == itemId,
          orElse: () => null,
        );

        if (item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Livro nao encontrado.')),
          );
        }

        if (item.isNew) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            ref.read(libraryControllerProvider.notifier).markItemSeen(item.id);
          });
        }

        return _BookDetailView(item: item);
      },
    );
  }
}

class _BookDetailView extends ConsumerWidget {
  final LibraryItem item;

  const _BookDetailView({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: colors.onSurface,
                  size: 20,
                ),
              ),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                tooltip: 'Remover da estante',
                onPressed: () => _confirmRemove(context, ref),
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildCoverHero(context),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppChip(type: _chipType),
                      if (item.isNew) const AppChip(type: ChipType.newItem),
                      AppChip(
                        type: item.origin == ItemOrigin.online
                            ? ChipType.online
                            : ChipType.local,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  if (item.author != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.author!,
                      style: TextStyle(
                        fontSize: 16,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _buildManagementActions(context, ref),
                  if (item.progress > 0) ...[
                    const SizedBox(height: 20),
                    _buildProgressCard(context),
                  ],
                  const SizedBox(height: 24),
                  _buildActions(context),
                  if (item.description != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Sinopse',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.description!,
                      style: TextStyle(
                        fontSize: 15,
                        color: colors.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverHero(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      fit: StackFit.expand,
      children: [
        LibraryItemCover(
          item: item,
          borderRadius: BorderRadius.zero,
          iconSize: 100,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                background.withValues(alpha: 0.0),
                background.withValues(alpha: 0.55),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pages = item.totalPages > 0
        ? '${item.currentPage} / ${item.totalPages} paginas'
        : '';
    final percent = '${(item.progress * 100).toStringAsFixed(0)}%';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Progresso',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                percent,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _coverColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppProgressBar(value: item.progress, color: _coverColor, height: 6),
          if (pages.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              pages,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final route = _routeForItem;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => context.push(route),
            icon: Icon(
              item.type == ItemType.audio
                  ? Icons.play_circle_outline_rounded
                  : Icons.menu_book_rounded,
              size: 20,
            ),
            label: Text(_primaryActionLabel),
          ),
        ),
        if (_showListenButton) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/listen/${item.id}'),
              icon: const Icon(Icons.headphones_rounded, size: 20),
              label: const Text('Ouvir'),
            ),
          ),
        ],
        if (item.progress > 0) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push(route),
              icon: const Icon(Icons.restart_alt_rounded, size: 20),
              label: Text(_restartActionLabel),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildManagementActions(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          selected: item.isFavorite,
          avatar: Icon(
            item.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            size: 18,
            color: item.isFavorite ? AppColors.onPrimary : AppColors.primary,
          ),
          label: const Text('Favorito'),
          onSelected: (_) => ref
              .read(libraryControllerProvider.notifier)
              .toggleFavorite(item.id),
          selectedColor: AppColors.primary,
          checkmarkColor: AppColors.onPrimary,
          labelStyle: TextStyle(
            color: item.isFavorite ? colors.onPrimary : colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          side: BorderSide(
            color: item.isFavorite ? AppColors.primary : AppColors.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        for (final status in LibraryItemStatus.values)
          ChoiceChip(
            selected: item.status == status,
            label: Text(_statusLabel(status)),
            onSelected: (_) => ref
                .read(libraryControllerProvider.notifier)
                .updateStatus(item.id, status),
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: item.status == status
                  ? colors.onPrimary
                  : colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            side: BorderSide(
              color: item.status == status
                  ? AppColors.primary
                  : AppColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ActionChip(
          avatar: const Icon(
            Icons.delete_outline_rounded,
            size: 18,
            color: AppColors.error,
          ),
          label: const Text('Remover'),
          onPressed: () => _confirmRemove(context, ref),
          labelStyle: const TextStyle(
            color: AppColors.error,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover da estante?'),
        content: Text(
          'Isso remove "${item.title}" da sua estante e apaga o progresso salvo no app. O arquivo original do celular nao sera apagado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Remover'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(libraryControllerProvider.notifier).removeItem(item.id);
    if (!context.mounted) return;
    context.go('/library');
  }

  Color get _coverColor {
    switch (item.type) {
      case ItemType.pdf:
        return AppColors.primary;
      case ItemType.hq:
        return AppColors.comicAccent;
      case ItemType.audio:
        return AppColors.audioAccent;
      case ItemType.ebook:
        return AppColors.primaryContainer;
      case ItemType.document:
        return AppColors.localAccent;
      case ItemType.text:
        return AppColors.textSecondary;
    }
  }

  ChipType get _chipType {
    switch (item.type) {
      case ItemType.pdf:
        return ChipType.pdf;
      case ItemType.hq:
        return ChipType.hq;
      case ItemType.audio:
        return ChipType.audio;
      case ItemType.ebook:
        return ChipType.ebook;
      case ItemType.document:
        return ChipType.document;
      case ItemType.text:
        return ChipType.text;
    }
  }

  String get _routeForItem {
    switch (item.type) {
      case ItemType.audio:
        return '/audio/${item.id}';
      case ItemType.pdf:
        return '/reader/${item.id}';
      case ItemType.hq:
        return '/hq/${item.id}';
      case ItemType.ebook:
        return EbookFormatSupport.canReadInternally(item)
            ? '/epub/${item.id}'
            : '/document/${item.id}';
      case ItemType.document:
      case ItemType.text:
        return '/document/${item.id}';
    }
  }

  String get _primaryActionLabel {
    if (item.type == ItemType.audio) {
      return item.progress > 0 ? 'Continuar ouvindo' : 'Ouvir';
    }
    return item.progress > 0 ? AppStrings.continueReading : 'Ler';
  }

  bool get _showListenButton {
    switch (item.type) {
      case ItemType.pdf:
        return true;
      case ItemType.ebook:
        return EbookFormatSupport.canReadInternally(item);
      case ItemType.text:
        return true;
      case ItemType.audio:
      case ItemType.hq:
      case ItemType.document:
        return false;
    }
  }

  String get _restartActionLabel {
    return item.type == ItemType.audio ? 'Ouvir do inicio' : 'Ler do inicio';
  }

  String _statusLabel(LibraryItemStatus status) {
    switch (status) {
      case LibraryItemStatus.toRead:
        return 'Para ler';
      case LibraryItemStatus.reading:
        return 'Lendo';
      case LibraryItemStatus.finished:
        return 'Lido';
    }
  }
}
