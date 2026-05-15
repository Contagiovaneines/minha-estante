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
import '../../library/presentation/library_controller.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(authControllerProvider);
    final libraryState = ref.watch(libraryControllerProvider);

    final user = userState.value;
    final items = libraryState.value ?? [];
    final reading = items.where((e) => e.progress > 0 && e.progress < 1).length;

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
              _buildStatsCard(items.length, reading),
              const SizedBox(height: 20),
              const SizedBox(height: 20),
              if (user != null) _buildMenuSection(context, ref, user),
              const SizedBox(height: 20),
              _buildLogoutCard(context, ref),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(AppUser user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _editProfile(context, ref, user),
            child: CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primary,
              backgroundImage:
                  LocalStorageService.getProfileImage(user.id) != null
                  ? FileImage(
                      File(LocalStorageService.getProfileImage(user.id)!),
                    )
                  : null,
              child: LocalStorageService.getProfileImage(user.id) == null
                  ? Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
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
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: const TextStyle(
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

  Widget _buildStatsCard(int books, int reading) {
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
    final showSources = LocalStorageService.isDriveEnabled(user.id);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (showSources) ...[
            _MenuItem(
              icon: Icons.cloud_outlined,
              label: AppStrings.mySourcesOnline,
              onTap: () => context.go('/sources'),
            ),
            const Divider(height: 1, indent: 56),
          ],
          _MenuItem(
            icon: Icons.add_to_drive_rounded,
            label: 'Configurar Google Drive',
            onTap: () => context.push('/drive_setup'),
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.edit_rounded,
            label: 'Editar perfil',
            onTap: () => _editProfile(context, ref, user),
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.lock_outline_rounded,
            label: 'Mudar senha',
            onTap: () => _changePassword(context, ref),
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.palette_outlined,
            label: AppStrings.appTheme,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tema em breve disponível!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.favorite_border_rounded,
            label: 'Apoie o Projeto (Doação)',
            color: AppColors.comicAccent,
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

  Widget _buildLogoutCard(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: _MenuItem(
        icon: Icons.logout_rounded,
        label: AppStrings.logout,
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
        title: const Text('Limpar cache'),
        content: const Text(
          'Isso removerá todos os itens da biblioteca e o progresso de leitura. As fontes serão mantidas.',
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

    if (confirm == true) {
      await LocalStorageService.clearCache(user.id);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.cacheCleared),
            backgroundColor: AppColors.localAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Deseja sair da sua conta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  void _showDonation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apoie o Projeto ❤️'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Este app é gratuito, mas caso queira contribuir e apoiar o desenvolvimento contínuo, envie um PIX para a chave abaixo:',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'meu.pix.aqui@email.com',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(
                  const ClipboardData(text: 'meu.pix.aqui@email.com'),
                );
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar perfil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () async {
                final result = await FilePicker.pickFiles(type: FileType.image);
                if (result != null && result.files.single.path != null) {
                  await LocalStorageService.setProfileImage(
                    user.id,
                    result.files.single.path!,
                  );
                  setState(() {});
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Foto atualizada!')),
                    );
                  }
                }
              },
              child: CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.surfaceContainer,
                backgroundImage:
                    LocalStorageService.getProfileImage(user.id) != null
                    ? FileImage(
                        File(LocalStorageService.getProfileImage(user.id)!),
                      )
                    : null,
                child: LocalStorageService.getProfileImage(user.id) == null
                    ? const Icon(
                        Icons.camera_alt_rounded,
                        color: AppColors.textSecondary,
                      )
                    : null,
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
                    .updateProfile(name: ctrl.text);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _changePassword(BuildContext context, WidgetRef ref) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mudar senha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              decoration: const InputDecoration(labelText: 'Senha atual'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              decoration: const InputDecoration(labelText: 'Nova senha'),
              obscureText: true,
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
              if (oldCtrl.text.isEmpty || newCtrl.text.isEmpty) return;
              try {
                await ref
                    .read(authControllerProvider.notifier)
                    .updatePassword(
                      oldPassword: oldCtrl.text,
                      newPassword: newCtrl.text,
                    );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Senha atualizada com sucesso!'),
                      backgroundColor: AppColors.localAccent,
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
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
    final c = color ?? AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: c, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c,
                  ),
                ),
              ),
              Icon(
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
