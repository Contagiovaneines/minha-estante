import 'dart:io';
import 'package:flutter/material.dart';
import '../../domain/ocr_service.dart';
import '../../domain/translation_service.dart';

enum _OverlayState { loading, done, error, empty }

class TranslationOverlay extends StatefulWidget {
  final File imageFile;
  final TranslationLang sourceLang;
  final VoidCallback onClose;
  final ValueChanged<TranslationLang> onLangChanged;

  const TranslationOverlay({
    super.key,
    required this.imageFile,
    required this.sourceLang,
    required this.onClose,
    required this.onLangChanged,
  });

  @override
  State<TranslationOverlay> createState() => _TranslationOverlayState();
}

class _TranslationOverlayState extends State<TranslationOverlay> {
  final _ocr = OcrService();
  final _translator = TranslationService();

  _OverlayState _state = _OverlayState.loading;
  PageOcrResult? _result;
  String _statusMessage = 'Iniciando...';
  int _progressCurrent = 0;
  int _progressTotal = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _process();
  }

  @override
  void didUpdateWidget(covariant TranslationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageFile.path != widget.imageFile.path ||
        oldWidget.sourceLang != widget.sourceLang) {
      _process();
    }
  }

  Future<void> _process() async {
    setState(() {
      _state = _OverlayState.loading;
      _statusMessage = 'Iniciando...';
      _progressCurrent = 0;
      _progressTotal = 0;
      _result = null;
      _errorMessage = null;
    });

    try {
      final result = await _ocr.processPage(
        widget.imageFile,
        widget.sourceLang,
        _translator,
        onStatus: (msg) {
          if (mounted) setState(() => _statusMessage = msg);
        },
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _progressCurrent = current;
              _progressTotal = total;
              _statusMessage = 'Traduzindo $current/$total...';
            });
          }
        },
      );

      if (!mounted) return;

      if (result.skippedBecauseAlreadyPortuguese ||
          result.skippedBecauseUnknownLanguage) {
        widget.onClose();
        return;
      }

      setState(() {
        _result = result;
        _state = result.isEmpty ? _OverlayState.empty : _OverlayState.done;
      });
    } catch (error, stackTrace) {
      debugPrint('Erro OCR: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _state = _OverlayState.error;
        _errorMessage =
            'Não foi possível executar o OCR nesta página. Tente novamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
        if (_state != _OverlayState.done) _buildCentralCard(),
        if (_state == _OverlayState.done && _result != null)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return _TranslationBlocksLayer(
                  result: _result!,
                  availableSize: Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ),
                );
              },
            ),
          ),
        _buildTopBar(),
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
      ],
    );
  }

  Widget _buildCentralCard() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_state == _OverlayState.loading) ...[
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              if (_progressTotal > 0) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _progressCurrent / _progressTotal,
                  backgroundColor: Colors.white24,
                  color: Colors.lightBlueAccent,
                ),
                const SizedBox(height: 6),
                Text(
                  '$_progressCurrent / $_progressTotal blocos',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ] else if (_state == _OverlayState.empty) ...[
              const Icon(
                Icons.text_fields_rounded,
                color: Colors.white54,
                size: 40,
              ),
              const SizedBox(height: 12),
              const Text(
                'Nenhum texto detectado nesta página.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tente outro idioma ou uma página com mais texto visível.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ] else if (_state == _OverlayState.error) ...[
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Erro desconhecido.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _process,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: const Text(
                  'Tentar novamente',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _glassButton(
                icon: Icons.close_rounded,
                onTap: widget.onClose,
                tooltip: 'Fechar tradução',
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.translate_rounded,
                      color: Colors.white70,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.sourceLang.label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '→ PT-BR',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _glassButton(
                icon: Icons.refresh_rounded,
                onTap: _process,
                tooltip: 'Reprocessar',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: TranslationLang.values.map((lang) {
                final isSelected = lang == widget.sourceLang;
                return GestureDetector(
                  onTap: () => widget.onLangChanged(lang),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      lang.label,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white60,
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TranslationBlocksLayer extends StatelessWidget {
  final PageOcrResult result;
  final Size availableSize;

  const _TranslationBlocksLayer({
    required this.result,
    required this.availableSize,
  });

  (double scale, double offsetX, double offsetY) _computeTransform() {
    final imgW = result.originalImageSize.width;
    final imgH = result.originalImageSize.height;
    final scrW = availableSize.width;
    final scrH = availableSize.height;

    if (imgW == 0 || imgH == 0) return (1, 0, 0);

    final scaleX = scrW / imgW;
    final scaleY = scrH / imgH;
    final scale = scaleX < scaleY ? scaleX : scaleY;

    final renderedW = imgW * scale;
    final renderedH = imgH * scale;
    final offsetX = (scrW - renderedW) / 2;
    final offsetY = (scrH - renderedH) / 2;

    return (scale, offsetX, offsetY);
  }

  @override
  Widget build(BuildContext context) {
    final (scale, offsetX, offsetY) = _computeTransform();

    return Stack(
      children: List.generate(result.blocks.length, (i) {
        final block = result.blocks[i];
        if (i >= result.translations.length) return const SizedBox.shrink();
        final translated = result.translations[i];
        if (translated == block.text) return const SizedBox.shrink();

        final box = block.boundingBox;
        final left = box.left * scale + offsetX;
        final top = box.top * scale + offsetY;
        final width = box.width * scale;

        return Positioned(
          left: left.clamp(0, availableSize.width - 60),
          top: top.clamp(0, availableSize.height - 20),
          width: width.clamp(80, availableSize.width * 0.85),
          child: _TranslatedBubble(
            original: block.text,
            translated: translated,
          ),
        );
      }),
    );
  }
}

class _TranslatedBubble extends StatefulWidget {
  final String original;
  final String translated;

  const _TranslatedBubble({required this.original, required this.translated});

  @override
  State<_TranslatedBubble> createState() => _TranslatedBubbleState();
}

class _TranslatedBubbleState extends State<_TranslatedBubble> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => setState(() => _showOriginal = !_showOriginal),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: _showOriginal
              ? Colors.amber.withValues(alpha: 0.93)
              : Colors.white.withValues(alpha: 0.93),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: _showOriginal ? Colors.amber.shade700 : Colors.black26,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 3,
              offset: Offset(1, 1),
            ),
          ],
        ),
        child: Text(
          _showOriginal ? widget.original : widget.translated,
          style: TextStyle(
            color: _showOriginal ? Colors.black87 : Colors.black,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
