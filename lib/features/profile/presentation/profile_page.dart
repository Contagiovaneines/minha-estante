import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/providers/ads_provider.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../../core/widgets/fake_monetization_slot.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_item.dart';
import '../../library/presentation/library_controller.dart';
import '../domain/backup_service.dart';

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
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                  color: colors.onSurface,
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
              const SizedBox(height: 20),
              const FakeMonetizationSlot(placement: 'profile_bottom'),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(AppUser user) {
    final imagePath = LocalStorageService.getProfileImage(user.id);
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outline),
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
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Perfil local neste aparelho',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
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
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.statistics,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
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
              Container(width: 1, height: 50, color: colors.outlineVariant),
              Expanded(
                child: _StatItem(
                  value: '$reading',
                  label: AppStrings.reading,
                  icon: Icons.bookmark_rounded,
                  color: AppColors.localAccent,
                ),
              ),
              Container(width: 1, height: 50, color: colors.outlineVariant),
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
    final isDark = ref.watch(themeModeProvider);
    final showAds = ref.watch(adsProvider);
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        children: [
          _MenuItem(
            icon: Icons.headphones_rounded,
            label: 'Audiobooks',
            onTap: () => context.go('/audiobooks'),
          ),
          Divider(height: 1, indent: 56, color: colors.outlineVariant),
          _MenuItem(
            icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            label: isDark ? AppStrings.themeLight : AppStrings.themeDark,
            onTap: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          Divider(height: 1, indent: 56, color: colors.outlineVariant),
          _MenuItem(
            icon: Icons.edit_rounded,
            label: 'Editar perfil local',
            onTap: () => _editProfile(context, ref, user),
          ),
          Divider(height: 1, indent: 56, color: colors.outlineVariant),
          _MenuItem(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacidade',
            onTap: () => context.go('/privacy'),
          ),
          Divider(height: 1, indent: 56, color: colors.outlineVariant),
          _MenuItem(
            icon: showAds ? Icons.money_off_rounded : Icons.campaign_rounded,
            label: showAds ? 'Desativar propagandas' : 'Ativar propagandas',
            onTap: () {
              if (showAds) {
                _showDisableAdsModal(context, ref);
              } else {
                ref.read(adsProvider.notifier).toggleAds(true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Propagandas ativadas. Obrigado pelo apoio!'),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          Divider(height: 1, indent: 56, color: colors.outlineVariant),
          _MenuItem(
            icon: Icons.volunteer_activism_rounded,
            label: 'Contribuir com PIX',
            color: AppColors.audioAccent,
            onTap: () => _showDonation(context),
          ),
          Divider(height: 1, indent: 56, color: colors.outlineVariant),
          _MenuItem(
            icon: Icons.upload_file_rounded,
            label: AppStrings.exportBackup,
            onTap: () => _exportBackup(context, ref),
          ),
          Divider(height: 1, indent: 56, color: colors.outlineVariant),
          _MenuItem(
            icon: Icons.download_rounded,
            label: 'Importar backup',
            onTap: () => _importBackup(context, ref),
          ),
          Divider(height: 1, indent: 56, color: colors.outlineVariant),
          _MenuItem(
            icon: Icons.bar_chart_rounded,
            label: 'Estatísticas',
            onTap: () => context.push('/statistics'),
          ),
          Divider(height: 1, indent: 56, color: colors.outlineVariant),
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
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
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

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    try {
      final importResult = await BackupService().importBackup(path, user.id);
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${importResult.summary}'),
          backgroundColor: AppColors.localAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao importar: ${e.toString().replaceFirst("Exception: ", "")}',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    try {
      final path = await BackupService().exportBackup(user.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppStrings.exportBackupSuccess}\n$path'),
          backgroundColor: AppColors.localAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.exportBackupError),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
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

  void _showDisableAdsModal(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _DisableAdsModalContent(
        ref: ref,
        onDonationTap: () {
          Navigator.pop(ctx);
          _showDonation(context);
        },
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
              child: CircleAvatar(
                radius: 40,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    final colors = Theme.of(context).colorScheme;
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
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
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
    final colors = Theme.of(context).colorScheme;
    final itemColor = color ?? colors.onSurface;

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
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisableAdsModalContent extends StatefulWidget {
  final WidgetRef ref;
  final VoidCallback onDonationTap;

  const _DisableAdsModalContent({
    required this.ref,
    required this.onDonationTap,
  });

  @override
  State<_DisableAdsModalContent> createState() => _DisableAdsModalContentState();
}

class _DisableAdsModalContentState extends State<_DisableAdsModalContent> {
  bool _showCheckbox = false;
  bool _isChecked = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _showCheckbox = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.campaign_rounded,
              size: 48,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Sobre as Propagandas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'As propagandas são usadas apenas para ajudar nos custos do projeto.\n\nElas foram pensadas para NUNCA atrapalhar a sua leitura de livros, HQs ou audição de audiobooks.\n\nSe preferir, você pode desativá-las totalmente de graça. Mas se quiser apoiar o app de outra forma para continuarmos trazendo melhorias, considere fazer uma contribuição voluntária!',
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_showCheckbox)
              Row(
                children: [
                  Checkbox(
                    value: _isChecked,
                    onChanged: (val) => setState(() => _isChecked = val ?? false),
                    activeColor: AppColors.primary,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isChecked = !_isChecked),
                      child: Text(
                        'Li e concordo em desativar as propagandas',
                        style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            if (_showCheckbox) const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isChecked
                  ? () {
                      widget.ref.read(adsProvider.notifier).toggleAds(false);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Propagandas desativadas com sucesso.'),
                          backgroundColor: AppColors.localAccent,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.block_rounded),
              label: const Text('Desativar Propagandas'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.surfaceContainerHighest,
                foregroundColor: colors.onSurface,
                disabledBackgroundColor: colors.surfaceContainerHighest.withValues(alpha: 0.3),
                disabledForegroundColor: colors.onSurface.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: widget.onDonationTap,
              icon: const Icon(Icons.volunteer_activism_rounded),
              label: const Text('Quero ajudar com PIX'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                widget.ref.read(adsProvider.notifier).toggleAds(true);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Propagandas ativadas. Obrigado pelo apoio!'),
                    backgroundColor: AppColors.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Manter propagandas ativas'),
            ),
          ],
        ),
      ),
    );
  }
}

