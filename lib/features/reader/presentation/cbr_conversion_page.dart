import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../library/domain/library_item.dart';
import '../domain/cbr_to_cbz_converter_service.dart';
import 'hq_reader_page.dart';

/// Tela intermediária exibida enquanto um arquivo CBR é convertido para CBZ.
/// Após a conversão, navega automaticamente para o leitor de HQ.
class CbrConversionPage extends StatefulWidget {
  final LibraryItem item;

  const CbrConversionPage({super.key, required this.item});

  @override
  State<CbrConversionPage> createState() => _CbrConversionPageState();
}

class _CbrConversionPageState extends State<CbrConversionPage> {
  final _service = CbrToCbzConverterService();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _convert();
  }

  Future<void> _convert() async {
    final path = widget.item.localPath;

    if (path == null) {
      _showError('Caminho do arquivo não encontrado.');
      return;
    }

    try {
      final cbzFile = await _service.convertPathOrUriToCbz(
        path,
        displayName: widget.item.relativePath ?? widget.item.title,
      );

      if (!mounted) return;

      // Substitui esta tela pelo leitor HQ diretamente após o frame atual
      // para evitar erro de '_debugLocked' no Navigator.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final convertedItem = widget.item.copyWith(localPath: cbzFile.path);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HqReaderDirectPage(item: convertedItem),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _errorMessage != null ? _buildError() : _buildLoading(),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.comicAccent),
          const SizedBox(height: 24),
          Text(
            widget.item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Convertendo CBR para CBZ...',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Isso pode levar alguns segundos.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Não foi possível abrir este CBR',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Voltar'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(180, 48)),
            ),
          ],
        ),
      ),
    );
  }
}
