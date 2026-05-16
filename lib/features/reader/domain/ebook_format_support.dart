import 'package:path/path.dart' as p;

import '../../library/domain/library_item.dart';

enum EbookFormat { epub, mobi, azw, azw3, kfx, unknown }

class EbookFormatSupport {
  EbookFormatSupport._();

  static EbookFormat detect(LibraryItem item) {
    for (final value in [
      item.localPath,
      item.relativePath,
      item.remoteUrl,
      item.title,
    ]) {
      final format = _detectFromPath(value);
      if (format != EbookFormat.unknown) return format;
    }
    return EbookFormat.unknown;
  }

  static bool canReadInternally(LibraryItem item) {
    return detect(item) == EbookFormat.epub;
  }

  static String labelFor(LibraryItem item) {
    switch (detect(item)) {
      case EbookFormat.epub:
        return 'EPUB';
      case EbookFormat.mobi:
        return 'MOBI';
      case EbookFormat.azw:
        return 'AZW';
      case EbookFormat.azw3:
        return 'AZW3';
      case EbookFormat.kfx:
        return 'KFX';
      case EbookFormat.unknown:
        return 'ebook';
    }
  }

  static EbookFormat _detectFromPath(String? value) {
    if (value == null || value.trim().isEmpty) return EbookFormat.unknown;
    final ext = p.extension(value.split('?').first).replaceFirst('.', '');
    switch (ext.toLowerCase()) {
      case 'epub':
        return EbookFormat.epub;
      case 'mobi':
        return EbookFormat.mobi;
      case 'azw':
        return EbookFormat.azw;
      case 'azw3':
        return EbookFormat.azw3;
      case 'kfx':
        return EbookFormat.kfx;
      default:
        return EbookFormat.unknown;
    }
  }
}
