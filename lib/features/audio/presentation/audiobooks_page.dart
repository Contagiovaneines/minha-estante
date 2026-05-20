import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/fake_monetization_slot.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_item.dart';
import '../../library/presentation/library_controller.dart';
import 'audio_queue_provider.dart';
import 'audiobook_player_page.dart';

class AudiobooksPage extends ConsumerStatefulWidget {
  const AudiobooksPage({super.key});

  @override
  ConsumerState<AudiobooksPage> createState() => _AudiobooksPageState();
}

class _AudiobooksPageState extends ConsumerState<AudiobooksPage> {
  static const _audioExtensions = ['mp3', 'm4a', 'm4b', 'aac', 'wav', 'opus'];
  final _searchController = TextEditingController();
  bool _isImporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickAudiobooks() async {
    final user = ref.read(authControllerProvider).value;
    if (user == null || _isImporting) return;

    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _audioExtensions,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _isImporting = true);
    try {
      final uuid = const Uuid();
      final now = DateTime.now();
      final items = result.files
          .where((file) => file.path != null && file.path!.trim().isNotEmpty)
          .map((file) {
            final path = file.path!;
            return LibraryItem(
              id: uuid.v4(),
              userId: user.id,
              sourceId: 'audiobooks_manual_${user.id}',
              title: p.basenameWithoutExtension(file.name),
              collectionId: 'audiobooks_${user.id}',
              collectionName: 'Audiobooks',
              relativePath: file.name,
              type: ItemType.audio,
              origin: ItemOrigin.local,
              localPath: path,
              isNew: true,
              createdAt: now,
              updatedAt: now,
            );
          })
          .toList();

      if (items.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nao foi possivel acessar os arquivos escolhidos.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await ref.read(libraryControllerProvider.notifier).addItems(items);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${items.length} audiobook(s) adicionados.'),
          backgroundColor: AppColors.localAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryControllerProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? null : _pickAudiobooks,
        icon: _isImporting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add_rounded),
        label: Text(_isImporting ? 'Adicionando' : 'Adicionar'),
      ),
      body: SafeArea(
        child: libraryState.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.audioAccent),
          ),
          error: (error, _) => Center(
            child: Text('Erro: $error', style: TextStyle(color: colors.error)),
          ),
          data: (items) {
            final audiobooks = _filteredAudiobooks(items);
            final continueItems = audiobooks
                .where((item) => (item.positionSeconds ?? 0) > 0)
                .toList();
            final showContinue = continueItems.isNotEmpty && audiobooks.length >= 4;

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(audiobooks.length)),
                SliverToBoxAdapter(child: _buildSearch()),
                if (showContinue) ...[
                  SliverToBoxAdapter(
                    child: _buildContinueSection(continueItems),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                      child: Text(
                        'Todos os áudios',
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(
                  child: FakeMonetizationSlot(placement: 'audiobooks_list'),
                ),
                if (audiobooks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  SliverList.separated(
                    itemCount: audiobooks.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = audiobooks[index];
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          index == 0 ? 8 : 0,
                          20,
                          index == audiobooks.length - 1 ? 110 : 0,
                        ),
                        child: _AudiobookTile(
                          item: item,
                          onTap: () => context.push('/audio/${item.id}'),
                          onAddToQueue: (it) {
                            ref
                                .read(audioQueueProvider.notifier)
                                .addToQueue(it.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '"${it.title}" adicionado à fila',
                                ),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: AppColors.audioAccent,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<LibraryItem> _filteredAudiobooks(List<LibraryItem> items) {
    final query = _searchController.text.trim().toLowerCase();
    final result = items.where((item) => item.type == ItemType.audio).toList();
    if (query.isEmpty) return result;
    return result
        .where(
          (item) =>
              item.title.toLowerCase().contains(query) ||
              (item.author?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  Widget _buildHeader(int count) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audiobooks',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  count == 1 ? '1 audio salvo' : '$count audios salvos',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.audioAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.headphones_rounded,
              color: AppColors.audioAccent,
              size: 26,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Buscar audiobook',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Limpar busca',
                ),
        ),
      ),
    );
  }

  Widget _buildContinueSection(List<LibraryItem> items) {
    final visible = items.take(2).toList();
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Continuar ouvindo',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          for (final item in visible) ...[
            _AudiobookTile(
              item: item,
              compact: true,
              onTap: () => context.push('/audio/${item.id}'),
            ),
            if (item != visible.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.audioAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.headphones_rounded,
                color: AppColors.audioAccent,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Nenhum audiobook ainda',
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Toque em Adicionar para escolher MP3, M4A, M4B, AAC, WAV ou OPUS do celular.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudiobookTile extends ConsumerWidget {
  final LibraryItem item;
  final VoidCallback onTap;
  final void Function(LibraryItem item)? onAddToQueue;
  final bool compact;

  const _AudiobookTile({
    required this.item,
    required this.onTap,
    this.onAddToQueue,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentItemId = ref.watch(currentAudiobookItemIdProvider);
    final isCurrent = currentItemId == item.id;

    if (!isCurrent) {
      return _buildTile(
        context,
        isPlaying: false,
        position: item.positionSeconds ?? 0,
        percent: item.progress.clamp(0.0, 1.0),
      );
    }

    final player = ref.watch(audiobookAudioPlayerProvider);

    return StreamBuilder<bool>(
      stream: player.playingStream,
      initialData: player.playing,
      builder: (context, playingSnapshot) {
        final isPlaying = playingSnapshot.data ?? false;

        return StreamBuilder<Duration>(
          stream: player.positionStream,
          initialData: player.position,
          builder: (context, positionSnapshot) {
            final positionDuration =
                positionSnapshot.data ?? Duration(seconds: item.positionSeconds ?? 0);
            final position = positionDuration.inSeconds;

            final duration = item.durationSeconds ?? 0;
            final percent = duration > 0
                ? (position / duration).clamp(0.0, 1.0)
                : item.progress.clamp(0.0, 1.0);

            return _buildTile(
              context,
              isPlaying: isPlaying,
              position: position,
              percent: percent,
            );
          },
        );
      },
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required bool isPlaying,
    required int position,
    required double percent,
  }) {
    final duration = item.durationSeconds ?? 0;
    final hasProgress = position > 0 || percent > 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 48 : 56,
              height: compact ? 48 : 56,
              decoration: BoxDecoration(
                color: AppColors.audioAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: AppColors.audioAccent,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    hasProgress
                        ? (isPlaying
                            ? 'Reproduzindo ${Formatters.formatDuration(position)}'
                            : 'Parou em ${Formatters.formatDuration(position)}')
                        : _fileLabel(item.localPath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  if (!compact && hasProgress) ...[
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: percent > 0 ? percent : null,
                        minHeight: 5,
                        color: AppColors.audioAccent,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  duration > 0 ? Formatters.formatDuration(duration) : '',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (onAddToQueue != null && !compact)
                  IconButton(
                    onPressed: () => onAddToQueue!(item),
                    icon: const Icon(Icons.queue_music_rounded, size: 20),
                    color: AppColors.audioAccent,
                    tooltip: 'Adicionar à fila',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fileLabel(String? path) {
    if (path == null || path.trim().isEmpty) return 'Arquivo de audio';
    final file = File(path);
    final ext = p.extension(file.path).replaceFirst('.', '').toUpperCase();
    return ext.isEmpty ? 'Arquivo de audio' : 'Arquivo $ext';
  }
}
