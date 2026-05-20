import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../domain/ocr_service.dart';
import '../../domain/translation_service.dart';
import '../../domain/tts_speaker_service.dart';

class _BubbleColors {
  final Color backgroundColor;
  final Color textColor;

  const _BubbleColors({required this.backgroundColor, required this.textColor});
}

enum _OverlayState { loading, done, error, empty }

class TranslationOverlay extends StatefulWidget {
  final File imageFile;
  final TranslationLang sourceLang;
  final VoidCallback onClose;
  final ValueChanged<TranslationLang> onLangChanged;
  final TransformationController? transformationController;
  final GestureTapDownCallback? onDoubleTapDown;
  final GestureTapCallback? onDoubleTap;

  const TranslationOverlay({
    super.key,
    required this.imageFile,
    required this.sourceLang,
    required this.onClose,
    required this.onLangChanged,
    this.transformationController,
    this.onDoubleTapDown,
    this.onDoubleTap,
  });

  @override
  State<TranslationOverlay> createState() => _TranslationOverlayState();
}

class _TranslationOverlayState extends State<TranslationOverlay> {
  final _ocr = OcrService();
  final _translator = TranslationService();

  _OverlayState _state = _OverlayState.loading;
  PageOcrResult? _result;
  Map<int, _BubbleColors> _bubbleColors = const {};
  String _statusMessage = 'Iniciando...';
  int _progressCurrent = 0;
  int _progressTotal = 0;
  String? _errorMessage;

  // Cooldown timer for rate-limiting
  int _currentCooldownDuration = 90;
  DateTime? _rateLimitHitAt;
  Timer? _cooldownTimer;
  int _cooldownRemaining = 0;

  @override
  void initState() {
    super.initState();
    _process();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    TtsSpeakerService.stop();
    super.dispose();
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
      _bubbleColors = const {};
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

      final bubbleColors = <int, _BubbleColors>{};
      try {
        final bytes = await widget.imageFile.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final decodedImage = frame.image;
        final byteData = await decodedImage.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );

        if (byteData != null) {
          for (var i = 0; i < result.blocks.length; i++) {
            final block = result.blocks[i];
            bubbleColors[i] = _detectBubbleColors(
              decodedImage,
              byteData,
              block.boundingBox,
            );
          }
        }
        decodedImage.dispose();
      } catch (e) {
        debugPrint('Erro ao extrair cores do balão: $e');
      }

      if (!mounted) return;

      setState(() {
        _result = result;
        _bubbleColors = bubbleColors;
        _state = result.isEmpty ? _OverlayState.empty : _OverlayState.done;
      });
    } catch (error, stackTrace) {
      debugPrint('Erro OCR/Tradução: $error\n$stackTrace');
      if (!mounted) return;

      String displayError;
      bool isRateLimited = false;
      final errorStr = error.toString();
      int parsedCooldown = 90;

      if (errorStr.contains('MYMEMORY WARNING')) {
        isRateLimited = true;
        displayError = 'Limite de traduções atingido.';

        int h = 0, m = 0, s = 0;
        final hMatch = RegExp(
          r'(\d+)\s+HOUR',
          caseSensitive: false,
        ).firstMatch(errorStr);
        if (hMatch != null) h = int.parse(hMatch.group(1)!);

        final mMatch = RegExp(
          r'(\d+)\s+MINUTE',
          caseSensitive: false,
        ).firstMatch(errorStr);
        if (mMatch != null) m = int.parse(mMatch.group(1)!);

        final sMatch = RegExp(
          r'(\d+)\s+SECOND',
          caseSensitive: false,
        ).firstMatch(errorStr);
        if (sMatch != null) s = int.parse(sMatch.group(1)!);

        final total = (h * 3600) + (m * 60) + s;
        if (total > 0) {
          parsedCooldown = total;
        } else {
          parsedCooldown = 24 * 3600; // 24h fallback
        }
      } else if (errorStr.contains('429_ERROR')) {
        isRateLimited = true;
        displayError = errorStr;
        parsedCooldown = 90;
      } else if (errorStr.contains('Limite de requisições') ||
          errorStr.contains('cotas diárias') ||
          errorStr.contains('429')) {
        isRateLimited = true;
        displayError = 'Limite de requisições atingido.';
        parsedCooldown = 90;
      } else if (errorStr.contains('Falha de rede') ||
          errorStr.contains('SocketException') ||
          errorStr.contains('ClientException') ||
          errorStr.contains('TimeoutException')) {
        displayError = 'Sem conexão com a internet. Verifique sua rede.';
      } else if (errorStr.contains('HTTP')) {
        displayError = 'Servidor de tradução indisponível. Tente novamente.';
      } else {
        displayError = 'Erro: ${errorStr.replaceFirst('Exception: ', '')}';
      }

      if (isRateLimited) {
        _currentCooldownDuration = parsedCooldown;
        _startCooldown();
      }

      setState(() {
        _state = _OverlayState.error;
        _errorMessage = displayError;
      });
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();

    // If we already have a running cooldown, use the remaining time
    if (_rateLimitHitAt != null) {
      final elapsed = DateTime.now().difference(_rateLimitHitAt!).inSeconds;
      final remaining = _currentCooldownDuration - elapsed;
      if (remaining > 0) {
        _cooldownRemaining = remaining;
        _startCooldownTicker();
        return;
      }
    }

    _rateLimitHitAt = DateTime.now();
    _cooldownRemaining = _currentCooldownDuration;
    _startCooldownTicker();
  }

  void _startCooldownTicker() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _cooldownTimer?.cancel();
        return;
      }
      setState(() {
        _cooldownRemaining--;
        if (_cooldownRemaining <= 0) {
          _cooldownRemaining = 0;
          _rateLimitHitAt = null;
          _cooldownTimer?.cancel();
        }
      });
    });
  }

  String _formatCooldown(int seconds) {
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildCooldownIndicator() {
    final progress = 1.0 - (_cooldownRemaining / _currentCooldownDuration);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                backgroundColor: Colors.white12,
                color: Colors.lightBlueAccent,
              ),
              Text(
                _formatCooldown(_cooldownRemaining),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'A cota da API renova em breve',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  _BubbleColors _detectBubbleColors(
    ui.Image image,
    ByteData byteData,
    Rect box,
  ) {
    final w = image.width;
    final h = image.height;

    final x1 = box.left.round().clamp(0, w - 1);
    final y1 = box.top.round().clamp(0, h - 1);
    final x2 = box.right.round().clamp(0, w - 1);
    final y2 = box.bottom.round().clamp(0, h - 1);

    final borderPixels = <Color>[];
    final stepX = math.max(1, (x2 - x1) ~/ 8);
    final stepY = math.max(1, (y2 - y1) ~/ 8);

    for (int x = x1; x <= x2; x += stepX) {
      borderPixels.add(_getPixelColor(byteData, w, x, y1));
      borderPixels.add(_getPixelColor(byteData, w, x, y2));
    }
    for (int y = y1; y <= y2; y += stepY) {
      borderPixels.add(_getPixelColor(byteData, w, x1, y));
      borderPixels.add(_getPixelColor(byteData, w, x2, y));
    }

    final bgColor = _getDominantColor(borderPixels);

    final innerPixels = <Color>[];
    final innerStepX = math.max(1, (x2 - x1) ~/ 12);
    final innerStepY = math.max(1, (y2 - y1) ~/ 12);
    for (int y = y1 + 2; y < y2 - 2; y += innerStepY) {
      for (int x = x1 + 2; x < x2 - 2; x += innerStepX) {
        innerPixels.add(_getPixelColor(byteData, w, x, y));
      }
    }

    Color textColor = Colors.black;
    double maxContrast = 0.0;
    for (final color in innerPixels) {
      final contrast = (color.computeLuminance() - bgColor.computeLuminance())
          .abs();
      if (contrast > maxContrast) {
        maxContrast = contrast;
        textColor = color;
      }
    }

    final bgLuminance = bgColor.computeLuminance();
    if (maxContrast < 0.25 ||
        (bgColor.red - textColor.red).abs() +
                (bgColor.green - textColor.green).abs() +
                (bgColor.blue - textColor.blue).abs() <
            90) {
      textColor = bgLuminance > 0.5 ? Colors.black : Colors.white;
    }

    Color finalBg = bgColor;
    if (bgLuminance > 0.92) {
      finalBg = Colors.white;
    } else if (bgLuminance < 0.12) {
      finalBg = Colors.black;
    }

    return _BubbleColors(backgroundColor: finalBg, textColor: textColor);
  }

  Color _getPixelColor(ByteData data, int width, int x, int y) {
    final offset = (y * width + x) * 4;
    if (offset + 3 >= data.lengthInBytes) return Colors.white;
    final r = data.getUint8(offset);
    final g = data.getUint8(offset + 1);
    final b = data.getUint8(offset + 2);
    final a = data.getUint8(offset + 3);
    return Color.fromARGB(a, r, g, b);
  }

  Color _getDominantColor(List<Color> pixels) {
    if (pixels.isEmpty) return Colors.white;

    final colorCounts = <int, int>{};
    for (final pixel in pixels) {
      final r = (pixel.red ~/ 16) * 16;
      final g = (pixel.green ~/ 16) * 16;
      final b = (pixel.blue ~/ 16) * 16;
      final key = (r << 16) | (g << 8) | b;
      colorCounts[key] = (colorCounts[key] ?? 0) + 1;
    }

    int bestKey = 0xFFFFFF;
    int maxCount = -1;
    colorCounts.forEach((key, count) {
      if (count > maxCount) {
        maxCount = count;
        bestKey = key;
      }
    });

    final r = (bestKey >> 16) & 0xFF;
    final g = (bestKey >> 8) & 0xFF;
    final b = bestKey & 0xFF;
    return Color.fromARGB(255, r, g, b);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    final callback = widget.onDoubleTapDown;
    if (callback == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    final localPosition =
        renderBox?.globalToLocal(details.globalPosition) ??
        details.localPosition;

    callback(
      TapDownDetails(
        globalPosition: details.globalPosition,
        localPosition: localPosition,
        kind: details.kind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_state == _OverlayState.done)
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: _handleDoubleTapDown,
              onDoubleTap: widget.onDoubleTap,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          )
        else
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
                final layer = _TranslationBlocksLayer(
                  result: _result!,
                  bubbleColors: _bubbleColors,
                  availableSize: Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  ),
                  onDoubleTapDown: _handleDoubleTapDown,
                  onDoubleTap: widget.onDoubleTap,
                );

                final transformController = widget.transformationController;
                if (transformController == null) return layer;

                return AnimatedBuilder(
                  animation: transformController,
                  child: layer,
                  builder: (context, child) {
                    return Transform(
                      transform: transformController.value,
                      alignment: Alignment.topLeft,
                      child: child,
                    );
                  },
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
              if (_cooldownRemaining > 0) ...[
                const SizedBox(height: 10),
                _buildCooldownIndicator(),
              ],
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _cooldownRemaining > 0 ? null : _process,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: _cooldownRemaining > 0 ? Colors.white38 : Colors.white,
                ),
                label: Text(
                  _cooldownRemaining > 0
                      ? 'Aguarde ${_formatCooldown(_cooldownRemaining)}'
                      : 'Tentar novamente',
                  style: TextStyle(
                    color: _cooldownRemaining > 0
                        ? Colors.white38
                        : Colors.white,
                  ),
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
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: TranslationLang.values.map((lang) {
                  final isSelected = lang == widget.sourceLang;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Tooltip(
                        message: lang.label,
                        child: GestureDetector(
                          onTap: () => widget.onLangChanged(lang),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                lang.shortLabel,
                                maxLines: 1,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.black
                                      : Colors.white70,
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
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
  final Map<int, _BubbleColors> bubbleColors;
  final Size availableSize;
  final GestureTapDownCallback? onDoubleTapDown;
  final GestureTapCallback? onDoubleTap;

  const _TranslationBlocksLayer({
    required this.result,
    required this.bubbleColors,
    required this.availableSize,
    this.onDoubleTapDown,
    this.onDoubleTap,
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
        final translated = result.translations[i].trim();
        if (translated.isEmpty) return const SizedBox.shrink();
        if (translated == block.text.trim() &&
            TranslationService.isLikelyProperName(block.text)) {
          return const SizedBox.shrink();
        }

        final box = _paddedBlockRect(block);
        final left = box.left * scale + offsetX;
        final top = box.top * scale + offsetY;
        final right = box.right * scale + offsetX;
        final bottom = box.bottom * scale + offsetY;
        final viewportBox = _clampRectToViewport(
          Rect.fromLTRB(left, top, right, bottom),
        );

        if (viewportBox.width < 8 || viewportBox.height < 8) {
          return const SizedBox.shrink();
        }

        final colors =
            bubbleColors[i] ??
            const _BubbleColors(
              backgroundColor: Colors.white,
              textColor: Colors.black,
            );

        return Positioned(
          left: viewportBox.left,
          top: viewportBox.top,
          width: viewportBox.width,
          height: viewportBox.height,
          child: _TranslatedBubble(
            original: block.text,
            translated: translated,
            maxFontSize: _estimatedFontSize(block, scale),
            backgroundColor: colors.backgroundColor,
            textColor: colors.textColor,
            onDoubleTapDown: onDoubleTapDown,
            onDoubleTap: onDoubleTap,
          ),
        );
      }),
    );
  }

  Rect _paddedBlockRect(OcrBlock block) {
    final box = block.boundingBox;
    final lineHeight = _estimatedLineHeight(block);
    final horizontalPadding = math.max(
      math.max(lineHeight * 0.28, 2.5),
      math.min(box.width * 0.14, 12.0),
    );
    final verticalPadding = math.max(
      math.max(lineHeight * 0.42, 3.5),
      math.min(box.height * 0.20, 14.0),
    );

    return Rect.fromLTRB(
      math.max(0, box.left - horizontalPadding),
      math.max(0, box.top - verticalPadding),
      math.min(result.originalImageSize.width, box.right + horizontalPadding),
      math.min(result.originalImageSize.height, box.bottom + verticalPadding),
    );
  }

  Rect _clampRectToViewport(Rect rect) {
    final left = rect.left.clamp(0.0, availableSize.width);
    final top = rect.top.clamp(0.0, availableSize.height);
    final right = rect.right.clamp(0.0, availableSize.width);
    final bottom = rect.bottom.clamp(0.0, availableSize.height);

    return Rect.fromLTRB(
      math.min(left, right),
      math.min(top, bottom),
      math.max(left, right),
      math.max(top, bottom),
    );
  }

  double _estimatedLineHeight(OcrBlock block) {
    final heights =
        block.lineBoxes
            .map((box) => box.height)
            .where((height) => height > 0)
            .toList()
          ..sort();

    if (heights.isNotEmpty) return heights[heights.length ~/ 2];

    final lineCount = block.text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    return block.boundingBox.height / math.max(lineCount, 1);
  }

  double _estimatedFontSize(OcrBlock block, double scale) {
    final size = _estimatedLineHeight(block) * scale * 0.78;
    return size.clamp(4.5, 18.0);
  }
}

class _TranslatedBubble extends StatefulWidget {
  final String original;
  final String translated;
  final double maxFontSize;
  final Color backgroundColor;
  final Color textColor;
  final GestureTapDownCallback? onDoubleTapDown;
  final GestureTapCallback? onDoubleTap;

  const _TranslatedBubble({
    required this.original,
    required this.translated,
    required this.maxFontSize,
    required this.backgroundColor,
    required this.textColor,
    this.onDoubleTapDown,
    this.onDoubleTap,
  });

  @override
  State<_TranslatedBubble> createState() => _TranslatedBubbleState();
}

class _TranslatedBubbleState extends State<_TranslatedBubble> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final displayText = _displayText;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: widget.onDoubleTapDown,
      onDoubleTap: widget.onDoubleTap,
      onLongPress: () => setState(() => _showOriginal = !_showOriginal),
      onTap: () {
        final text = _showOriginal ? widget.original : widget.translated;
        final lang = _showOriginal ? 'en-US' : 'pt-BR';
        TtsSpeakerService.speak(text, language: lang);
      },
      child: Container(
        clipBehavior: Clip.hardEdge,
        alignment: Alignment.center,
        padding: EdgeInsets.all((widget.maxFontSize * 0.12).clamp(0.8, 2.5)),
        decoration: BoxDecoration(
          color: _showOriginal
              ? Colors.amber.withValues(alpha: 0.90)
              : widget.backgroundColor,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: _showOriginal
                ? Colors.amber.shade700
                : widget.backgroundColor,
            width: 0.5,
          ),
        ),
        child: _AutoFitText(
          text: displayText,
          maxFontSize: widget.maxFontSize,
          minFontSize: math.min(4.0, widget.maxFontSize),
          color: _showOriginal ? Colors.black87 : widget.textColor,
        ),
      ),
    );
  }

  String get _displayText {
    final text = _showOriginal ? widget.original : widget.translated;
    if (_showOriginal) return text;

    return _originalLooksUppercase(widget.original) ? text.toUpperCase() : text;
  }

  bool _originalLooksUppercase(String value) {
    final letters = RegExp(r'[A-Za-z]').allMatches(value).toList();
    if (letters.length < 4) return false;

    final uppercase = letters
        .where((match) => match.group(0) == match.group(0)!.toUpperCase())
        .length;
    return uppercase / letters.length >= 0.70;
  }
}

class _AutoFitText extends StatelessWidget {
  final String text;
  final double maxFontSize;
  final double minFontSize;
  final Color color;

  const _AutoFitText({
    required this.text,
    required this.maxFontSize,
    required this.minFontSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fittedFontSize = _fitFontSize(
          text: _withBreakOpportunities(text),
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          textDirection: Directionality.of(context),
        );

        return Text(
          _withBreakOpportunities(text),
          textAlign: TextAlign.center,
          softWrap: true,
          overflow: TextOverflow.clip,
          style: GoogleFonts.comicNeue(
            color: color,
            fontSize: fittedFontSize,
            fontWeight: FontWeight.w800,
            height: 1.02,
            letterSpacing: -0.2,
          ),
        );
      },
    );
  }

  double _fitFontSize({
    required String text,
    required double maxWidth,
    required double maxHeight,
    required TextDirection textDirection,
  }) {
    if (maxWidth <= 0 || maxHeight <= 0) return minFontSize;

    var low = minFontSize;
    var high = maxFontSize;

    for (var i = 0; i < 12; i++) {
      final mid = (low + high) / 2;
      if (_fits(
        text: text,
        fontSize: mid,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        textDirection: textDirection,
      )) {
        low = mid;
      } else {
        high = mid;
      }
    }

    return low;
  }

  bool _fits({
    required String text,
    required double fontSize,
    required double maxWidth,
    required double maxHeight,
    required TextDirection textDirection,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: GoogleFonts.comicNeue(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.02,
          letterSpacing: -0.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: textDirection,
      maxLines: null,
    )..layout(maxWidth: maxWidth);

    return painter.width <= maxWidth + 0.1 && painter.height <= maxHeight + 0.1;
  }

  String _withBreakOpportunities(String value) {
    return value.splitMapJoin(
      RegExp(r'\S{13,}'),
      onMatch: (match) => _splitLongToken(match.group(0)!),
      onNonMatch: (text) => text,
    );
  }

  String _splitLongToken(String value) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      buffer.write(value[i]);
      if ((i + 1) % 7 == 0 && i != value.length - 1) {
        buffer.write('\u200B');
      }
    }
    return buffer.toString();
  }
}
