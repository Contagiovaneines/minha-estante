import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final error = await ref
        .read(sourcesControllerProvider.notifier)
        .addSource(name: _nameCtrl.text, url: _linkCtrl.text);

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fonte adicionada e sincronizada com sucesso!'),
          backgroundColor: AppColors.localAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text(AppStrings.addDrive),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                _buildDriveIcon(),
                const SizedBox(height: 32),
                AppTextField(
                  controller: _nameCtrl,
                  label: AppStrings.shelfName,
                  hintText: 'Ex: Meus PDFs de Tecnologia',
                  prefixIcon: Icons.drive_file_rename_outline_rounded,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Informe um nome para a estante';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _linkCtrl,
                  label: AppStrings.drivePublicLink,
                  hintText: 'https://drive.google.com/drive/folders/...',
                  prefixIcon: Icons.link_rounded,
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Informe o link do Drive';
                    }
                    if (!v.contains('drive.google.com')) {
                      return 'Informe um link válido do Google Drive';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _buildInfoCard(),
                const SizedBox(height: 32),
                AppButton(
                  label: AppStrings.addLibrary,
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

  Widget _buildDriveIcon() {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(
            Icons.drive_folder_upload_rounded,
            size: 48,
            color: AppColors.primary,
          ),
        ),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.background, width: 2),
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppStrings.driveInfoText,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
