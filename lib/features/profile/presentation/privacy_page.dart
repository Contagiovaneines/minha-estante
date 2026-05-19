import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/profile'),
        ),
        title: const Text('Privacidade'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              'Politica de privacidade',
              style: GoogleFonts.playfairDisplay(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'O Minha Estante foi pensado como uma biblioteca local. Esta tela resume o comportamento atual do app e deve ser usada como base para a politica publica antes de subir na Play Store.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            _PrivacySection(
              icon: Icons.phone_android_rounded,
              title: 'Dados no aparelho',
              text:
                  'Itens da biblioteca, progresso, favoritos, perfil local e imagem de perfil ficam salvos no armazenamento local do app.',
            ),
            _PrivacySection(
              icon: Icons.folder_open_rounded,
              title: 'Arquivos do usuario',
              text:
                  'O app acessa apenas arquivos e pastas escolhidos pelo usuario. Limpar a biblioteca remove dados do app, mas nao apaga os arquivos originais do celular.',
            ),
            _PrivacySection(
              icon: Icons.headphones_rounded,
              title: 'Audiobooks',
              text:
                  'A reproducao de audio usa o arquivo selecionado e salva a ultima posicao localmente para continuar de onde parou.',
            ),
            _PrivacySection(
              icon: Icons.translate_rounded,
              title: 'OCR e traducao',
              text:
                  'Ao usar traducao em HQ/Manga, o texto reconhecido pode ser enviado ao servico de traducao configurado. Evite traduzir conteudo sensivel.',
            ),
            _PrivacySection(
              icon: Icons.volunteer_activism_rounded,
              title: 'PIX',
              text:
                  'O botao de contribuicao apenas exibe e copia uma chave PIX. O app nao processa pagamento e nao coleta dados bancarios.',
            ),
            _PrivacySection(
              icon: Icons.delete_outline_rounded,
              title: 'Exclusao',
              text:
                  'Use Perfil > Limpar biblioteca para remover itens e progresso salvos localmente. Tambem e possivel desinstalar o app para remover seus dados locais.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _PrivacySection({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
