import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show Rect, Size;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'translation_service.dart';

class OcrBlock {
  final String text;
  final Rect boundingBox;
  final List<Rect> lineBoxes;
  final List<String> recognizedLanguages;

  const OcrBlock({
    required this.text,
    required this.boundingBox,
    required this.lineBoxes,
    this.recognizedLanguages = const [],
  });
}

class PageOcrResult {
  final List<OcrBlock> blocks;
  final List<String> translations;
  final Size originalImageSize;
  final bool skippedBecauseAlreadyPortuguese;
  final bool skippedBecauseUnknownLanguage;

  const PageOcrResult({
    required this.blocks,
    required this.translations,
    required this.originalImageSize,
    this.skippedBecauseAlreadyPortuguese = false,
    this.skippedBecauseUnknownLanguage = false,
  });

  bool get isEmpty => blocks.isEmpty;
}

enum _OcrTranslationDecision { translate, alreadyPortuguese, unknownLanguage }

class OcrService {
  // ignore: unused_element
  TextRecognizer _recognizerFor(TranslationLang lang) {
    switch (lang) {
      case TranslationLang.japanese:
        return TextRecognizer(script: TextRecognitionScript.japanese);
      case TranslationLang.korean:
        return TextRecognizer(script: TextRecognitionScript.korean);
      case TranslationLang.chineseSimplified:
      case TranslationLang.chineseTraditional:
        return TextRecognizer(script: TextRecognitionScript.chinese);
      case TranslationLang.english:
        return TextRecognizer(script: TextRecognitionScript.latin);
    }
  }

  Future<Size> _getImageSize(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    codec.dispose();
    return size;
  }

  Future<List<OcrBlock>> _recognizeBlocks(
    File imageFile,
    TranslationLang lang,
  ) async {
    final recognizer = _recognizerFor(lang);
    final inputImage = InputImage.fromFilePath(imageFile.path);

    try {
      final recognized = await recognizer.processImage(inputImage);
      final blocks = <OcrBlock>[];

      for (final block in recognized.blocks) {
        final text = block.text.trim();
        if (text.isEmpty || text.length < 2) continue;
        final languages = _recognizedLanguagesForBlock(block);

        blocks.add(
          OcrBlock(
            text: text,
            boundingBox: block.boundingBox,
            lineBoxes: block.lines.map((l) => l.boundingBox).toList(),
            recognizedLanguages: languages,
          ),
        );
      }

      return blocks;
    } finally {
      await recognizer.close();
    }
  }

  static List<String> _recognizedLanguagesForBlock(TextBlock block) {
    final languages = <String>{};

    for (final language in block.recognizedLanguages) {
      final normalized = _normalizeLanguage(language);
      if (_isKnownLanguage(normalized)) languages.add(normalized);
    }

    for (final line in block.lines) {
      for (final language in line.recognizedLanguages) {
        final normalized = _normalizeLanguage(language);
        if (_isKnownLanguage(normalized)) languages.add(normalized);
      }
    }

    return languages.toList(growable: false);
  }

  static String _normalizeLanguage(String value) {
    return value.trim().toLowerCase().replaceAll('_', '-');
  }

  static bool _isKnownLanguage(String value) {
    return value.isNotEmpty &&
        value != 'und' &&
        value != 'unknown' &&
        value != 'zxx';
  }

  static bool _isPortugueseLanguage(String value) {
    final normalized = _normalizeLanguage(value);
    return normalized == 'pt' || normalized.startsWith('pt-');
  }

  static _OcrTranslationDecision _translationDecisionFor(
    List<OcrBlock> blocks,
  ) {
    var portugueseBlocks = 0;
    var foreignBlocks = 0;

    for (final block in blocks) {
      final languages = block.recognizedLanguages
          .map(_normalizeLanguage)
          .where(_isKnownLanguage)
          .toSet();

      if (languages.isEmpty) continue;

      final hasForeign = languages.any(
        (language) => !_isPortugueseLanguage(language),
      );

      if (hasForeign) {
        foreignBlocks++;
      } else {
        portugueseBlocks++;
      }
    }

    if (portugueseBlocks == 0 && foreignBlocks == 0) {
      return _OcrTranslationDecision.unknownLanguage;
    }

    if (portugueseBlocks > foreignBlocks) {
      return _OcrTranslationDecision.alreadyPortuguese;
    }

    return _OcrTranslationDecision.translate;
  }

  Future<PageOcrResult> processPage(
    File imageFile,
    TranslationLang lang,
    TranslationService translationService, {
    void Function(String status)? onStatus,
    void Function(int current, int total)? onProgress,
  }) async {
    onStatus?.call('Analisando imagem...');
    final imageSize = await _getImageSize(imageFile);

    onStatus?.call('Reconhecendo texto...');
    final blocks = await _recognizeBlocks(imageFile, lang);

    if (blocks.isEmpty) {
      return PageOcrResult(
        blocks: const [],
        translations: const [],
        originalImageSize: imageSize,
      );
    }

    onStatus?.call('Verificando idioma...');
    switch (_translationDecisionFor(blocks)) {
      case _OcrTranslationDecision.alreadyPortuguese:
        return PageOcrResult(
          blocks: blocks,
          translations: const [],
          originalImageSize: imageSize,
          skippedBecauseAlreadyPortuguese: true,
        );
      case _OcrTranslationDecision.unknownLanguage:
        return PageOcrResult(
          blocks: blocks,
          translations: const [],
          originalImageSize: imageSize,
          skippedBecauseUnknownLanguage: true,
        );
      case _OcrTranslationDecision.translate:
        break;
    }

    onStatus?.call('Traduzindo ${blocks.length} bloco(s)...');
    final texts = blocks.map((b) => b.text).toList();
    final translations = await translationService.translateBatch(
      texts,
      sourceLang: lang,
      onProgress: onProgress,
    );

    return PageOcrResult(
      blocks: blocks,
      translations: translations,
      originalImageSize: imageSize,
    );
  }
}
