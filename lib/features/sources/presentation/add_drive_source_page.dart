import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import 'sources_controller.dart';

class AddDriveSourcePage extends ConsumerStatefulWidget {
  const AddDriveSourcePage({super.key});

  @override
  ConsumerState<AddDriveSourcePage> createState() => _AddDriveSourcePageState();
}

class _AddDriveSourcePageState extends ConsumerState<AddDriveSourcePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  bool _isLoading = false;
  String? _statusMessage;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Iniciando importação...';
    });

    final result = await ref
        .read(driveImportControllerProvider.notifier)
        .startPublicFileImport(name: _nameCtrl.text, url: _linkCtrl.text);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _statusMessage = result.isError ? null : result.message;
    });
    if (result.isError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.localAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final importTasks = ref.watch(driveImportControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Adicionar link público'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                _buildHeader(),
                const SizedBox(height: 28),
                AppTextField(
                  controller: _nameCtrl,
                  label: 'Nome do arquivo',
                  hintText: 'Ex: One Piece Vol. 1',
                  prefixIcon: Icons.drive_file_rename_outline_rounded,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Informe um nome';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _linkCtrl,
                  label: 'Link público do arquivo',
                  hintText: 'https://drive.google.com/file/d/...',
                  prefixIcon: Icons.link_rounded,
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Informe o link';
                    if (!v.contains('drive.google.com') &&
                        !v.contains('usercontent.google.com')) {
                      return 'Use um link do Google Drive';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildFolderNote(),
                const SizedBox(height: 16),
                _buildSupportedFormats(),
                const SizedBox(height: 28),
                if (_statusMessage != null) ...[
                  _buildStartMessage(),
                  const SizedBox(height: 16),
                ],
                if (importTasks.isNotEmpty) ...[
                  _buildImportTasks(importTasks),
                  const SizedBox(height: 16),
                ],
                AppButton(
                  label: 'Adicionar à biblioteca',
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _submit,
                  icon: Icons.add_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStartMessage() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.localAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.localAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          if (_isLoading) ...[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.localAccent,
              ),
            ),
          ] else ...[
            const Icon(
              Icons.cloud_done_rounded,
              color: AppColors.localAccent,
              size: 18,
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _statusMessage!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportTasks(List<DriveImportTask> tasks) {
    final visibleTasks = tasks.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Importações recentes',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final task in visibleTasks) ...[
            _ImportTaskRow(task: task),
            if (task != visibleTasks.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(
            Icons.add_to_drive_rounded,
            size: 38,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Link público do Drive',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Cole o link de um arquivo público do Google Drive. '
          'Não é necessária nenhuma chave de API.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildFolderNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Links de pasta ainda não são suportados sem API key. '
              'Adicione cada arquivo individualmente.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportedFormats() {
    const formats = [
      ('PDF', Icons.picture_as_pdf_rounded, AppColors.primary),
      ('CBZ / CBR', Icons.auto_stories_rounded, AppColors.comicAccent),
      ('MP3 / AAC', Icons.headphones_rounded, AppColors.audioAccent),
      ('EPUB / MOBI*', Icons.menu_book_rounded, AppColors.primaryContainer),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Formatos suportados',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: formats.map((f) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(f.$2, size: 14, color: f.$3),
                  const SizedBox(width: 4),
                  Text(
                    f.$1,
                    style: TextStyle(
                      fontSize: 12,
                      color: f.$3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Text(
            '* Ebooks adicionados à estante, leitor ainda não disponível.',
            style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ImportTaskRow extends StatelessWidget {
  final DriveImportTask task;

  const _ImportTaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: task.isActive
              ? CircularProgressIndicator(
                  value: task.progress,
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                )
              : Icon(
                  task.status == DriveImportStatus.error
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: task.status == DriveImportStatus.error
                      ? AppColors.error
                      : AppColors.localAccent,
                  size: 18,
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                task.errorMessage ?? task.statusMessage,
                style: TextStyle(
                  color: task.status == DriveImportStatus.error
                      ? AppColors.error
                      : AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
