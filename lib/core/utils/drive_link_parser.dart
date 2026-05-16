class DriveLinkParser {
  DriveLinkParser._();

  static String? extractFolderId(String url) {
    final patterns = [
      RegExp(r'drive\.google\.com/drive(?:/u/\d+)?/folders/([a-zA-Z0-9_-]+)'),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static String? extractFileId(String url) {
    final patterns = [
      RegExp(r'drive\.google\.com/file/d/([a-zA-Z0-9_-]+)'),
      RegExp(r'drive\.google\.com/open\?(?:.*&)?id=([a-zA-Z0-9_-]+)'),
      RegExp(r'drive\.google\.com/uc\?(?:.*&)?id=([a-zA-Z0-9_-]+)'),
      RegExp(
        r'drive\.usercontent\.google\.com/download\?(?:.*&)?id=([a-zA-Z0-9_-]+)',
      ),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static bool isFolder(String url) => url.contains('/folders/');

  static bool isFile(String url) =>
      url.contains('/file/d/') ||
      url.contains('open?id=') ||
      url.contains('uc?id=') ||
      url.contains('uc?') ||
      url.contains('usercontent.google.com');

  static bool isValidDriveUrl(String url) =>
      url.contains('drive.google.com') ||
      url.contains('usercontent.google.com');

  static String? extractId(String url) =>
      extractFileId(url) ?? extractFolderId(url);

  static String buildDirectDownloadUrl(String fileId) {
    return 'https://drive.usercontent.google.com/download'
        '?id=$fileId&export=download&confirm=t';
  }

  static String buildUcDownloadUrl(String fileId) {
    return 'https://drive.google.com/uc?export=download&id=$fileId&confirm=t';
  }

  static String buildViewUrl(String fileId) {
    return 'https://drive.google.com/file/d/$fileId/view';
  }

  static String? extractFilenameFromContentDisposition(String? header) {
    if (header == null) return null;

    final match = RegExp(
      'filename\\*?=["\\\']?(?:UTF-8\\\'\\\')?([^;"\\\']+)',
      caseSensitive: false,
    ).firstMatch(header);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;

    return Uri.decodeComponent(value.replaceAll('"', '').replaceAll("'", ''));
  }

  static ItemFileType detectTypeFromName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return ItemFileType.pdf;
      case 'cbz':
      case 'zip':
        return ItemFileType.cbz;
      case 'cbr':
      case 'rar':
        return ItemFileType.cbr;
      case 'epub':
      case 'mobi':
      case 'azw':
      case 'azw3':
      case 'kfx':
        return ItemFileType.epub;
      case 'mp3':
      case 'm4a':
      case 'm4b':
      case 'aac':
      case 'wav':
      case 'opus':
        return ItemFileType.audio;
      default:
        return ItemFileType.unknown;
    }
  }
}

enum ItemFileType { pdf, cbz, cbr, epub, audio, unknown }
