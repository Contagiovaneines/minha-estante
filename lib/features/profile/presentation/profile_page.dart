import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_item.dart';
import '../../library/presentation/library_controller.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    final items = ref.watch(libraryControllerProvider).value ?? [];
    final reading = items.where((e) => e.progress > 0 && e.progress < 1).length;
    final audiobooks = items.where((e) => e.type == ItemType.audio).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.profile,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              if (user != null) _buildProfileCard(user),
              const SizedBox(height: 20),
              _buildStatsCard(items.length, reading, audiobooks),
              const SizedBox(height: 20),
              if (user != null) _buildMenuSection(context, ref, user),
              const SizedBox(height: 20),
              _buildExitCard(context, ref),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(AppUser user) {
    final imagePath = LocalStorageService.getProfileImage(user.id);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _editProfile(context, ref, user),
            child: CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primary,
              backgroundImage: imagePath != null
                  ? FileImage(File(imagePath))
                  : null,
              child: imagePath == null
                  ? Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : 'L',
                      style: const TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Perfil local neste aparelho',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(int books, int reading, int audiobooks) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AppStrings.statistics,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  value: '$books',
                  label: AppStrings.books,
                  icon: Icons.auto_stories_rounded,
                  color: AppColors.primary,
                ),
              ),
              Container(width: 1, height: 50, color: AppColors.border),
              Expanded(
                child: _StatItem(
                  value: '$reading',
                  label: AppStrings.reading,
                  icon: Icons.bookmark_rounded,
                  color: AppColors.localAccent,
                ),
              ),
              Container(width: 1, height: 50, color: AppColors.border),
              Expanded(
                child: _StatItem(
                  value: '$audiobooks',
                  label: 'Audios',
                  icon: Icons.headphones_rounded,
                  color: AppColors.audioAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection(BuildContext context, WidgetRef ref, AppUser user) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _MenuItem(
            icon: Icons.headphones_rounded,
            label: 'Audiobooks',
            onTap: () => context.go('/audiobooks'),
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.edit_rounded,
            label: 'Editar perfil local',
            onTap: () => _editProfile(context, ref, user),
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacidade',
            onTap: () => context.go('/privacy'),
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.volunteer_activism_rounded,
            label: 'Contribuir com PIX',
            color: AppColors.audioAccent,
            onTap: () => _showDonation(context),
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.cleaning_services_outlined,
            label: AppStrings.clearCache,
            onTap: () => _clearCache(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildExitCard(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: _MenuItem(
        icon: Icons.logout_rounded,
        label: 'Voltar para a tela inicial',
        color: AppColors.error,
        onTap: () => _logout(context, ref),
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar biblioteca'),
        content: const Text(
          'Isso remove os itens salvos no app e o progresso local. Os arquivos originais do celular nao sao apagados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Limpar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await LocalStorageService.clearCache(user.id);
    await ref.read(libraryControllerProvider.notifier).refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(AppStrings.cacheCleared),
        backgroundColor: AppColors.localAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).logout();
  }

  void _showDonation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apoie o Projeto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Este app e gratuito. Se quiser contribuir com a comunidade e apoiar novas atualizacoes, envie um PIX para a chave abaixo:',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const SelectableText(
                AppStrings.pixKey,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: AppStrings.pixKey));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chave PIX copiada!')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copiar PIX'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _editProfile(BuildContext context, WidgetRef ref, AppUser user) {
    final ctrl = TextEditingController(text: user.name);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar perfil local'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.pickFiles(type: FileType.image);
                if (result == null || result.files.single.path == null) return;

                await LocalStorageService.setProfileImage(
                  user.id,
                  result.files.single.path!,
                );
                setState(() {});
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
              },
              child: const CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.surfaceContainer,
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Nome'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                await ref
                    .read(authControllerProvider.notifier)
                    .updateProfile(name: ctrl.text.trim());
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final itemColor = color ?? AppColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: itemColor, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: itemColor,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.border,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
