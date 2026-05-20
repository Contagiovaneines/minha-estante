import 'package:flutter_tts/flutter_tts.dart';

class TtsSpeakerService {
  static final _tts = FlutterTts();
  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;
    await _tts.setLanguage('pt-BR');
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
    _initialized = true;
  }

  static Future<void> speak(String text, {String language = 'pt-BR'}) async {
    await _init();
    try {
      await _tts.setLanguage(language);
    } catch (_) {}
    await _tts.speak(text);
  }

  static Future<void> stop() async {
    await _tts.stop();
  }
}
