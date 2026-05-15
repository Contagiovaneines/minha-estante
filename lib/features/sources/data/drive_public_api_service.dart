import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/utils/drive_link_parser.dart';
import '../../library/domain/library_item.dart';

const String _driveApiKey = String.fromEnvironment('DRIVE_API_KEY');

class DrivePublicApiService {
  bool get hasApiKey => _driveApiKey.isNotEmpty;

  static const _audioExtensions = {'mp3', 'm4a', 'aac'};
  static const _hqExtensions = {'cbr', 'cbz', 'cb7', 'cbt', 'cba'};
  static const _ebookExtensions = {'epub', 'mobi', 'azw3', 'kfx'};

  Future<List<LibraryItem>> syncSource({
    required String userId,
    required String sourceId,
    required String driveId,
    required bool isFolder,
  }) async {
    if (!hasApiKey) {
      throw Exception('API_KEY_MISSING');
    }

    if (isFolder) {
      return _fetchFolder(
        userId: userId,
        sourceId: sourceId,
        folderId: driveId,
      );
    } else {
      return _fetchFile(userId: userId, sourceId: sourceId, fileId: driveId);
    }
  }

  Future<List<LibraryItem>> _fetchFolder({
    required String userId,
    required String sourceId,
    required String folderId,
    String? pageToken,
    List<LibraryItem>? accumulated,
  }) async {
    final items = accumulated ?? <LibraryItem>[];
    final url = DriveLinkParser.buildListUrl(
      folderId,
      _driveApiKey,
      pageToken: pageToken,
    );

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('PERMISSION_DENIED');
    }
    if (response.statusCode == 404) {
      throw Exception('NOT_FOUND');
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP_ERROR_${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final files = (data['files'] as List<dynamic>?) ?? [];
    final nextPageToken = data['nextPageToken'] as String?;

    for (final file in files) {
      final item = _fileToItem(file as Map<String, dynamic>, userId, sourceId);
      if (item != null) items.add(item);
    }

    if (nextPageToken != null) {
      return _fetchFolder(
        userId: userId,
        sourceId: sourceId,
        folderId: folderId,
        pageToken: nextPageToken,
        accumulated: items,
      );
    }

    if (items.isEmpty) {
      throw Exception('FOLDER_EMPTY');
    }

    return items;
  }

  Future<List<LibraryItem>> _fetchFile({
    required String userId,
    required String sourceId,
    required String fileId,
  }) async {
    final url = DriveLinkParser.buildMetaUrl(fileId, _driveApiKey);
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('PERMISSION_DENIED');
    }
    if (response.statusCode == 404) {
      throw Exception('NOT_FOUND');
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP_ERROR_${response.statusCode}');
    }

    final file = jsonDecode(response.body) as Map<String, dynamic>;
    final item = _fileToItem(file, userId, sourceId);
    if (item == null) throw Exception('UNSUPPORTED_FILE');
    return [item];
  }

  LibraryItem? _fileToItem(
    Map<String, dynamic> file,
    String userId,
    String sourceId,
  ) {
    final name = file['name'] as String? ?? '';
    final mimeType = file['mimeType'] as String? ?? '';
    final id = file['id'] as String? ?? '';
    final thumbnail = file['thumbnailLink'] as String?;
    final modifiedTime = file['modifiedTime'] as String?;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final type = _itemTypeForExtension(ext, mimeType);

    if (type == null) return null;

    final now = modifiedTime != null
        ? DateTime.parse(modifiedTime)
        : DateTime.now();
    final downloadUrl = DriveLinkParser.buildDownloadUrl(id, _driveApiKey);

    return LibraryItem(
      id: 'drive_$id',
      userId: userId,
      sourceId: sourceId,
      title: name.contains('.')
          ? name.substring(0, name.lastIndexOf('.'))
          : name,
      type: type,
      origin: ItemOrigin.online,
      driveFileId: id,
      remoteUrl: downloadUrl,
      thumbnailUrl: thumbnail,
      isNew: true,
      createdAt: now,
      updatedAt: now,
    );
  }

  ItemType? _itemTypeForExtension(String ext, String mimeType) {
    if (ext == 'pdf' || mimeType.contains('pdf')) return ItemType.pdf;
    if (_audioExtensions.contains(ext) || mimeType.contains('audio')) {
      return ItemType.audio;
    }
    if (_hqExtensions.contains(ext)) return ItemType.hq;
    if (_ebookExtensions.contains(ext)) return ItemType.ebook;
    if (ext == 'doc' || ext == 'docx') return ItemType.document;
    if (ext == 'txt' || mimeType.startsWith('text/')) return ItemType.text;
    return null;
  }

  String getFriendlyError(String code) {
    switch (code) {
      case 'API_KEY_MISSING':
        return 'Chave da API do Google Drive nao configurada. Execute o app com --dart-define=DRIVE_API_KEY=SUA_CHAVE.';
      case 'PERMISSION_DENIED':
        return 'Permissao negada. Certifique-se de que o link e publico e configurado como "Qualquer pessoa com o link pode ver".';
      case 'NOT_FOUND':
        return 'Arquivo ou pasta nao encontrado. Verifique o link informado.';
      case 'FOLDER_EMPTY':
        return 'A pasta nao contem arquivos compativeis.';
      case 'UNSUPPORTED_FILE':
        return 'O arquivo informado nao e suportado nesta biblioteca.';
      default:
        return 'Erro ao acessar o Google Drive. Verifique o link e tente novamente.';
    }
  }
}
