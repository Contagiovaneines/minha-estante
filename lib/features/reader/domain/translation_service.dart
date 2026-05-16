import 'dart:convert';
import 'package:http/http.dart' as http;

enum TranslationLang {
  japanese('ja', '🇯🇵 Japonês'),
  korean('ko', '🇰🇷 Coreano'),
  chineseSimplified('zh-CN', '🇨🇳 Chinês Simpl.'),
  chineseTraditional('zh-TW', '🇨🇳 Chinês Trad.'),
  english('en', '🇺🇸 Inglês');

  final String code;
  final String label;
  const TranslationLang(this.code, this.label);

  static TranslationLang fromCode(String code) {
    return TranslationLang.values.firstWhere(
      (l) => l.code == code,
      orElse: () => TranslationLang.japanese,
    );
  }
}

class TranslationService {
  static const _baseUrl = 'https://api.mymemory.translated.net/get';
  static const _maxChunkLength = 500;

  Future<String> translate(
    String text, {
    TranslationLang sourceLang = TranslationLang.japanese,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    if (_isPortugueseCode(sourceLang.code)) return trimmed;

    if (trimmed.length > _maxChunkLength) {
      return _translateInChunks(trimmed, sourceLang: sourceLang);
    }

    return _callApi(trimmed, sourceLang: sourceLang);
  }

  Future<String> _translateInChunks(
    String text, {
    required TranslationLang sourceLang,
  }) async {
    final lines = text.split('\n');
    final buffer = StringBuffer();
    var currentChunk = StringBuffer();

    for (final line in lines) {
      if (currentChunk.length + line.length > _maxChunkLength) {
        if (currentChunk.isNotEmpty) {
          final translated = await _callApi(
            currentChunk.toString(),
            sourceLang: sourceLang,
          );
          buffer.writeln(translated);
          currentChunk.clear();
        }
      }
      currentChunk.writeln(line);
    }

    if (currentChunk.isNotEmpty) {
      final translated = await _callApi(
        currentChunk.toString(),
        sourceLang: sourceLang,
      );
      buffer.write(translated);
    }

    return buffer.toString().trim();
  }

  Future<String> _callApi(
    String text, {
    required TranslationLang sourceLang,
  }) async {
    try {
      final uri = Uri.parse(_baseUrl).replace(
        queryParameters: {'q': text, 'langpair': '${sourceLang.code}|pt-BR'},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final responseData = data['responseData'] as Map<String, dynamic>?;
      final translated = responseData?['translatedText'] as String?;

      if (translated == null || translated.contains('MYMEMORY WARNING')) {
        return text;
      }

      return translated.trim();
    } catch (_) {
      return text;
    }
  }

  Future<List<String>> translateBatch(
    List<String> texts, {
    TranslationLang sourceLang = TranslationLang.japanese,
    void Function(int current, int total)? onProgress,
  }) async {
    if (_isPortugueseCode(sourceLang.code)) {
      return texts;
    }

    final results = <String>[];

    for (var i = 0; i < texts.length; i++) {
      onProgress?.call(i + 1, texts.length);
      final translated = await translate(texts[i], sourceLang: sourceLang);
      results.add(translated);

      if (i < texts.length - 1) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    return results;
  }

  bool _isPortugueseCode(String code) {
    final normalized = code.trim().toLowerCase().replaceAll('_', '-');
    return normalized == 'pt' || normalized.startsWith('pt-');
  }
}
