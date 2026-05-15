import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import 'auth_controller.dart';

class DriveSetupPage extends ConsumerStatefulWidget {
  const DriveSetupPage({super.key});

  @override
  ConsumerState<DriveSetupPage> createState() => _DriveSetupPageState();
}

class _DriveSetupPageState extends ConsumerState<DriveSetupPage> {
  final _apiKeyCtrl = TextEditingController();
  bool _useDrive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authControllerProvider).value;
      if (user != null) {
        setState(() {
          _useDrive = LocalStorageService.isDriveEnabled(user.id);
          _apiKeyCtrl.text = LocalStorageService.getDriveApiKey(user.id) ?? '';
        });
      }
    });
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _finish() async {
    final user = ref.read(authControllerProvider).value;
    if (user != null) {
      await LocalStorageService.saveDriveSettings(
        user.id,
        enabled: _useDrive,
        apiKey: _useDrive ? _apiKeyCtrl.text.trim() : null,
      );
    }
    if (mounted) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/library');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Icon(
                Icons.add_to_drive_rounded,
                size: 64,
                color: AppColors.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Usar o Google Drive?',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'O aplicativo pode se conectar ao seu Google Drive para ler HQs, PDFs, Epubs e Áudios diretamente de lá.\n\nPara isso, você precisa informar a sua chave de API pessoal, garantindo que só você terá acesso aos seus arquivos. Ou pode continuar sem usar o Drive (ler apenas arquivos do celular).',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: SwitchListTile(
                  value: _useDrive,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) {
                    setState(() => _useDrive = val);
                  },
                  title: const Text(
                    'Habilitar Google Drive',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  subtitle: const Text(
                    'Se desativado, a aba de fontes do Drive será escondida.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              if (_useDrive) ...[
                const SizedBox(height: 20),
                AppTextField(
                  controller: _apiKeyCtrl,
                  label:
                      'Sua Chave de API do Google (Opcional se usar pasta pública)',
                  hintText: 'AIzaSy...',
                  prefixIcon: Icons.key_rounded,
                ),
              ],
              const SizedBox(height: 48),
              AppButton(label: 'Continuar', onPressed: _finish),
            ],
          ),
        ),
      ),
    );
  }
}
