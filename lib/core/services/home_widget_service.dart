import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../features/library/domain/library_item.dart';

class HomeWidgetService {
  static const MethodChannel _channel = MethodChannel(
    'minha_estante/home_widget',
  );

  static Future<void> updateFromItem(LibraryItem item) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _channel.invokeMethod<void>('update', {
        'title': item.title,
        'subtitle': _subtitleFor(item),
        'progress': item.progress.clamp(0.0, 1.0),
      });
    } catch (_) {
      // Widgets are best-effort and should never block reading progress saves.
    }
  }

  static Future<void> clear() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _channel.invokeMethod<void>('clear');
    } catch (_) {
      // Best-effort only.
    }
  }

  static String _subtitleFor(LibraryItem item) {
    if (item.progress > 0) {
      return '${(item.progress * 100).clamp(0, 100).round()}% concluido';
    }
    switch (item.type) {
      case ItemType.audio:
        return 'Audiobook';
      case ItemType.pdf:
        return 'PDF';
      case ItemType.hq:
        return 'HQ';
      case ItemType.ebook:
        return 'Ebook';
      case ItemType.document:
        return 'Documento';
      case ItemType.text:
        return 'Texto';
    }
  }
}
