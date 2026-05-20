import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../library/domain/library_item.dart';
import '../../library/presentation/library_controller.dart';
import 'audio_queue_provider.dart';

class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(audioQueueProvider);
    final items = ref.watch(libraryControllerProvider).value ?? [];

    final queueItems = queue.itemIds
        .map(
          (id) => items.cast<LibraryItem?>().firstWhere(
            (item) => item?.id == id,
            orElse: () => null,
          ),
        )
        .where((item) => item != null)
        .cast<LibraryItem>()
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Fila de Reprodução',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          if (queue.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(audioQueueProvider.notifier).clear(),
              child: const Text(
                'Limpar',
                style: TextStyle(color: AppColors.error),
              ),
            ),
        ],
      ),
      body: queue.isEmpty
          ? _buildEmpty(context)
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: queueItems.length,
              onReorder: (old, newIdx) {
                ref.read(audioQueueProvider.notifier).reorder(old, newIdx);
              },
              itemBuilder: (context, index) {
                final item = queueItems[index];
                final isCurrent = index == queue.currentIndex;
                return _QueueTile(
                  key: ValueKey(item.id),
                  item: item,
                  isCurrent: isCurrent,
                  index: index,
                  onTap: () {
                    ref.read(audioQueueProvider.notifier).jumpTo(index);
                    context.push('/audio/${item.id}');
                  },
                  onRemove: () {
                    ref
                        .read(audioQueueProvider.notifier)
                        .removeFromQueue(item.id);
                  },
                );
              },
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.queue_music_rounded,
          size: 64,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          'Fila vazia',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Adicione audiobooks à fila\npela tela de Audiobooks.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      ],
    ),
  );
}

class _QueueTile extends StatelessWidget {
  final LibraryItem item;
  final bool isCurrent;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _QueueTile({
    required super.key,
    required this.item,
    required this.isCurrent,
    required this.index,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.audioAccent.withValues(alpha: 0.1)
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? AppColors.audioAccent
              : colors.outline.withValues(alpha: 0.4),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        onTap: onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.audioAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isCurrent ? Icons.play_arrow_rounded : Icons.headphones_rounded,
            color: AppColors.audioAccent,
            size: 24,
          ),
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
            color: isCurrent ? AppColors.audioAccent : colors.onSurface,
            fontSize: 14,
          ),
        ),
        subtitle: isCurrent
            ? const Text(
                'Tocando agora',
                style: TextStyle(
                  color: AppColors.audioAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              color: AppColors.error,
              tooltip: 'Remover da fila',
              onPressed: onRemove,
            ),
            Icon(Icons.drag_handle_rounded, color: colors.outline),
          ],
        ),
      ),
    );
  }
}
