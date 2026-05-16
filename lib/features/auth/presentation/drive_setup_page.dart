import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../../core/widgets/app_button.dart';
import 'auth_controller.dart';

class DriveSetupPage extends ConsumerStatefulWidget {
  const DriveSetupPage({super.key});

  @override
  ConsumerState<DriveSetupPage> createState() => _DriveSetupPageState();
}

class _DriveSetupPageState extends ConsumerState<DriveSetupPage> {
  bool _showSourcesTab = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authControllerProvider).value;
      if (user != null) {
        setState(() {
          _showSourcesTab = LocalStorageService.isDriveEnabled(user.id);
        });
      }
    });
  }

  void _finish() async {
    final user = ref.read(authControllerProvider).value;
    if (user != null) {
      await LocalStorageService.saveDriveSettings(
        user.id,
        enabled: _showSourcesTab,
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
              const Icon(
                Icons.add_to_drive_rounded,
                size: 64,
                color: AppColors.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Links do Google Drive',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Você pode adicionar links públicos de arquivos do Google Drive '
                'à sua biblioteca — sem precisar de conta Google ou chave de API.\n\n'
                'Suporta PDF, CBZ, CBR e arquivos de áudio.\n\n'
                'Ative abaixo para mostrar a aba "Fontes" no menu.',
                textAlign: TextAlign.center,
                style: TextStyle(
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
                  value: _showSourcesTab,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) => setState(() => _showSourcesTab = val),
                  title: const Text(
                    'Mostrar aba de Fontes online',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  subtitle: const Text(
                    'Permite adicionar e gerenciar links do Drive.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 48),
              AppButton(label: 'Continuar', onPressed: _finish),
            ],
          ),
        ),
      ),
    );
  }
}
