import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/loading_view.dart';
import '../../library/domain/library_source.dart';
import 'sources_controller.dart';
import 'widgets/source_card.dart';

class SourcesPage extends ConsumerWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesState = ref.watch(sourcesControllerProvider);
    final hasApiKey = ref.watch(driveApiServiceProvider).hasApiKey;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Minhas Fontes',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () => context.push('/sources/add'),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Adicionar'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Gerencie suas conexões do Google Drive.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (!hasApiKey) ...[
                    const SizedBox(height: 12),
                    const _ApiKeyBanner(),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Expanded(
              child: sourcesState.when(
                loading: () =>
                    const LoadingView(message: 'Carregando fontes...'),
                error: (e, _) => Center(child: Text('Erro: $e')),
                data: (sources) => sources.isEmpty
                    ? EmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: AppStrings.emptySources,
                        subtitle: AppStrings.emptySourcesSubtitle,
                        actionLabel: AppStrings.addSource,
                        onAction: () => context.push('/sources/add'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: sources.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return SourceCard(
                            source: sources[index],
                            onSync: () =>
                                _syncSource(context, ref, sources[index]),
                            onEdit: () =>
                                _editSource(context, ref, sources[index]),
                            onRemove: () =>
                                _removeSource(context, ref, sources[index]),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncSource(
    BuildContext context,
    WidgetRef ref,
    LibrarySource source,
  ) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Sincronizando...'),
          ],
        ),
        duration: Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
      ),
    );

    final error = await ref
        .read(sourcesControllerProvider.notifier)
        .syncSource(source);

    scaffold.hideCurrentSnackBar();

    if (error != null) {
      scaffold.showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      scaffold.showSnackBar(
        const SnackBar(
          content: Text(AppStrings.syncSuccess),
          backgroundColor: AppColors.localAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeSource(
    BuildContext context,
    WidgetRef ref,
    LibrarySource source,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover fonte'),
        content: Text(
          'Deseja remover "${source.name}"? Os livros desta fonte também serão removidos da biblioteca.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remover',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref
          .read(sourcesControllerProvider.notifier)
          .removeSource(source.id);
    }
  }

  Future<void> _editSource(
    BuildContext context,
    WidgetRef ref,
    LibrarySource source,
  ) async {
    final controller = TextEditingController(text: source.name);
    final formKey = GlobalKey<FormState>();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar fonte'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Nome da fonte'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Informe um nome para a fonte';
              }
              return null;
            },
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (name == null || name == source.name) return;

    await ref
        .read(sourcesControllerProvider.notifier)
        .updateSourceName(source: source, name: name);
  }
}

class _ApiKeyBanner extends StatelessWidget {
  const _ApiKeyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              AppStrings.noApiKey,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
