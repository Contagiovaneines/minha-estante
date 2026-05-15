class DriveLinkParser {
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
      RegExp(r'drive\.google\.com/open\?id=([a-zA-Z0-9_-]+)'),
      RegExp(r'drive\.google\.com/uc\?(?:.*&)?id=([a-zA-Z0-9_-]+)'),
      RegExp(r'drive\.google\.com/uc\?id=([a-zA-Z0-9_-]+)'),
    ];
    for (final p in patterns) {
      final match = p.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static bool isFolder(String url) {
    return url.contains('/folders/');
  }

  static bool isFile(String url) {
    return url.contains('/file/d/') ||
        url.contains('open?id=') ||
        url.contains('uc?id=') ||
        url.contains('uc?');
  }

  static bool isValidDriveUrl(String url) {
    return url.contains('drive.google.com') && (isFolder(url) || isFile(url));
  }

  static String? extractId(String url) {
    return extractFolderId(url) ?? extractFileId(url);
  }

  static String buildDownloadUrl(String fileId, String apiKey) {
    return 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=$apiKey';
  }

  static String buildListUrl(
    String folderId,
    String apiKey, {
    String? pageToken,
  }) {
    final q = Uri.encodeComponent("'$folderId' in parents and trashed = false");
    final fields = Uri.encodeComponent(
      'files(id,name,mimeType,size,modifiedTime,thumbnailLink),nextPageToken',
    );
    var url =
        'https://www.googleapis.com/drive/v3/files?q=$q&fields=$fields&key=$apiKey';
    if (pageToken != null) {
      url += '&pageToken=${Uri.encodeComponent(pageToken)}';
    }
    return url;
  }

  static String buildMetaUrl(String fileId, String apiKey) {
    final fields = Uri.encodeComponent(
      'id,name,mimeType,size,modifiedTime,thumbnailLink',
    );
    return 'https://www.googleapis.com/drive/v3/files/$fileId?fields=$fields&key=$apiKey';
  }
}
