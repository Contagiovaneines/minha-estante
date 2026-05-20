import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../storage/local_storage_service.dart';

final adsProvider = NotifierProvider<AdsNotifier, bool>(AdsNotifier.new);

class AdsNotifier extends Notifier<bool> {
  @override
  bool build() {
    return LocalStorageService.getSetting('show_ads') != 'false';
  }

  void toggleAds(bool show) {
    state = show;
    LocalStorageService.setSetting('show_ads', show ? 'true' : 'false');
  }
}
