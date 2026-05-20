import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/local_storage_service.dart';

const _themeKey = 'app_theme_dark';

/// Provides and persists the global theme mode (light / dark).
final themeModeProvider = NotifierProvider<ThemeModeNotifier, bool>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    final saved = LocalStorageService.getSetting(_themeKey);
    return saved == 'true';
  }

  void toggle() {
    state = !state;
    LocalStorageService.setSetting(_themeKey, state ? 'true' : 'false');
  }

  bool get isDark => state;
}
