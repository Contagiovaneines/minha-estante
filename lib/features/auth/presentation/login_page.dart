import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    await ref.read(authControllerProvider.notifier).enterAsGuest();

    if (!mounted) return;
    ref
        .read(authControllerProvider)
        .whenOrNull(
          error: (error, _) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error.toString().replaceFirst('Exception: ', '')),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 42, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),
              _buildLogo(),
              const SizedBox(height: 56),
              Text(
                'Sua biblioteca local',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Organize livros, HQs e audiobooks no seu celular. O app e gratuito e funciona como uma estante pessoal.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 44),
              _buildEnterButton(isLoading),
              const SizedBox(height: 16),
              _buildContributeButton(),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => _showPrivacySummary(context),
                child: const Text('Privacidade'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.menu_book_rounded,
            color: AppColors.onPrimary,
            size: 42,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.appName,
          style: GoogleFonts.playfairDisplay(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          AppStrings.appTagline,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildEnterButton(bool isLoading) {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : _enter,
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.login_rounded),
        label: Text(isLoading ? 'Entrando...' : 'Entrar'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF303033),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF303033),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildContributeButton() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.25 + (_pulse.value * 0.35);
        final scale = 1 + (_pulse.value * 0.018);

        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.audioAccent.withValues(alpha: glow),
                  blurRadius: 22 + (_pulse.value * 12),
                  spreadRadius: 1 + (_pulse.value * 3),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: SizedBox(
        height: 56,
        child: FilledButton.icon(
          onPressed: () => _showDonation(context),
          icon: const Icon(Icons.volunteer_activism_rounded),
          label: const Text('Contribuir com PIX'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.audioAccent,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  void _showDonation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contribua com o projeto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'O Minha Estante e gratuito. Se quiser contribuir com a comunidade e apoiar novas atualizacoes, use a chave PIX abaixo.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            SelectableText(
              AppStrings.pixKey,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.audioAccent,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: AppStrings.pixKey));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chave PIX copiada.'),
                    behavior: SnackBarBehavior.floating,
                  ),
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

  void _showPrivacySummary(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacidade'),
        content: const Text(
          'Seus livros, audiobooks e progresso ficam salvos localmente no aparelho. Ao usar OCR e traducao, o texto reconhecido pode ser enviado ao servico de traducao configurado.',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }
}
