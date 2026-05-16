import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/drive_link_parser.dart';
import '../../library/domain/library_item.dart';

class PublicLinkResult {
  final LibraryItem? item;
  final String? errorMessage;
  final bool isFolder;

  const PublicLinkResult({this.item, this.errorMessage, this.isFolder = false});

  bool get success => item != null;
}

class DrivePublicApiService {
  bool get hasApiKey => true;

  static const _supportedMimes = {
    'application/pdf',
    'application/zip',
    'application/x-cbz',
    'application/vnd.comicbook+zip',
    'application/x-cbr',
    'application/x-rar-compressed',
    'application/vnd.rar',
    'audio/mpeg',
    'audio/mp4',
    'audio/aac',
    'audio/wav',
    'audio/opus',
    'application/epub+zip',
    'application/x-mobipocket-ebook',
    'application/vnd.amazon.ebook',
  };

  Future<PublicLinkResult> processPublicLink({
    required String userId,
    required String sourceId,
    required String url,
    required String name,
    void Function(String status)? onStatus,
  }) async {
    if (DriveLinkParser.isFolder(url)) {
      return const PublicLinkResult(
        isFolder: true,
        errorMessage:
            'Pastas do Drive precisam de uma API key para listar arquivos. '
            'Por enquanto, adicione os arquivos individualmente colando o '
            'link de cada arquivo.',
      );
    }

    final fileId = DriveLinkParser.extractFileId(url);
    if (fileId == null) {
      return const PublicLinkResult(
        errorMessage:
            'Link inválido. Cole o link de um arquivo público do Google Drive.',
      );
    }

    onStatus?.call('Verificando arquivo...');

    final downloadUrl = DriveLinkParser.buildDirectDownloadUrl(fileId);
    http.Response headResponse;
    try {
      headResponse = await http
          .head(Uri.parse(downloadUrl))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return const PublicLinkResult(
        errorMessage:
            'Não foi possível acessar o arquivo. '
            'Verifique se o link é público e tente novamente.',
      );
    }

    if (headResponse.statusCode == 404) {
      return const PublicLinkResult(
        errorMessage: 'Arquivo não encontrado. Verifique o link.',
      );
    }

    if (headResponse.statusCode == 403 || headResponse.statusCode == 401) {
      return const PublicLinkResult(
        errorMessage:
            'Acesso negado. Certifique-se de que o arquivo está configurado como '
            '"Qualquer pessoa com o link pode ver".',
      );
    }

    final contentDisposition = headResponse.headers['content-disposition'];
    final contentType = headResponse.headers['content-type'];
    final detectedName =
        DriveLinkParser.extractFilenameFromContentDisposition(
          contentDisposition,
        ) ??
        name.trim();

    final fileType = _detectType(detectedName, contentType);

    if (fileType == ItemFileType.unknown) {
      return PublicLinkResult(
        errorMessage:
            'Formato não suportado: "$detectedName". '
            'Use PDF, CBZ, CBR, EPUB, MOBI, AZW3, KFX ou arquivos de áudio.',
      );
    }

    final now = DateTime.now();
    final itemTitle = p.basenameWithoutExtension(detectedName).trim().isEmpty
        ? name.trim()
        : p.basenameWithoutExtension(detectedName);

    if (fileType == ItemFileType.pdf) {
      final item = LibraryItem(
        id: 'drive_$fileId',
        userId: userId,
        sourceId: sourceId,
        title: itemTitle,
        type: ItemType.pdf,
        origin: ItemOrigin.online,
        driveFileId: fileId,
        remoteUrl: downloadUrl,
        relativePath: detectedName,
        isNew: true,
        createdAt: now,
        updatedAt: now,
      );
      return PublicLinkResult(item: item);
    }

    if (fileType == ItemFileType.audio) {
      final item = LibraryItem(
        id: 'drive_$fileId',
        userId: userId,
        sourceId: sourceId,
        title: itemTitle,
        type: ItemType.audio,
        origin: ItemOrigin.online,
        driveFileId: fileId,
        remoteUrl: downloadUrl,
        relativePath: detectedName,
        isNew: true,
        createdAt: now,
        updatedAt: now,
      );
      return PublicLinkResult(item: item);
    }

    if (fileType == ItemFileType.epub) {
      final item = LibraryItem(
        id: 'drive_$fileId',
        userId: userId,
        sourceId: sourceId,
        title: itemTitle,
        type: ItemType.ebook,
        origin: ItemOrigin.online,
        driveFileId: fileId,
        remoteUrl: downloadUrl,
        relativePath: detectedName,
        isNew: true,
        createdAt: now,
        updatedAt: now,
      );
      return PublicLinkResult(item: item);
    }

    onStatus?.call('Baixando HQ para o dispositivo...');

    try {
      final cachedFile = await _downloadToCache(
        fileId: fileId,
        fileName: detectedName,
        downloadUrl: downloadUrl,
        onStatus: onStatus,
      );

      final item = LibraryItem(
        id: 'drive_$fileId',
        userId: userId,
        sourceId: sourceId,
        title: itemTitle,
        type: ItemType.hq,
        origin: ItemOrigin.online,
        driveFileId: fileId,
        remoteUrl: downloadUrl,
        localPath: cachedFile.path,
        relativePath: detectedName,
        isNew: true,
        createdAt: now,
        updatedAt: now,
      );
      return PublicLinkResult(item: item);
    } catch (e) {
      return PublicLinkResult(
        errorMessage:
            'Não foi possível baixar o arquivo: '
            '${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  ItemFileType _detectType(String fileName, String? contentType) {
    final byName = DriveLinkParser.detectTypeFromName(fileName);
    if (byName != ItemFileType.unknown) return byName;

    final mime = contentType?.split(';').first.trim().toLowerCase();
    if (mime == null || !_supportedMimes.contains(mime)) {
      return ItemFileType.unknown;
    }

    if (mime == 'application/pdf') return ItemFileType.pdf;
    if (mime == 'application/epub+zip' ||
        mime == 'application/x-mobipocket-ebook' ||
        mime == 'application/vnd.amazon.ebook') {
      return ItemFileType.epub;
    }
    if (mime.startsWith('audio/')) return ItemFileType.audio;
    if (mime.contains('rar') || mime.contains('cbr')) return ItemFileType.cbr;
    return ItemFileType.cbz;
  }

  Future<File> _downloadToCache({
    required String fileId,
    required String fileName,
    required String downloadUrl,
    void Function(String status)? onStatus,
  }) async {
    final cacheDir = await getTemporaryDirectory();
    final hash = sha1.convert(utf8.encode(fileId)).toString().substring(0, 12);
    final ext = p.extension(fileName).isNotEmpty
        ? p.extension(fileName)
        : '.cbz';
    final targetDir = Directory(p.join(cacheDir.path, 'drive_cache'));
    if (!await targetDir.exists()) await targetDir.create(recursive: true);

    final targetFile = File(p.join(targetDir.path, '$hash$ext'));

    if (await targetFile.exists() && await targetFile.length() > 0) {
      return targetFile;
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(minutes: 10));

      if (streamedResponse.statusCode != 200) {
        throw Exception(
          'Servidor retornou ${streamedResponse.statusCode}. '
          'Verifique se o arquivo está público.',
        );
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      var receivedBytes = 0;

      final sink = targetFile.openWrite();
      try {
        await streamedResponse.stream.forEach((chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final percent = (receivedBytes / totalBytes * 100).round();
            onStatus?.call('Baixando... $percent%');
          }
        });
      } finally {
        await sink.flush();
        await sink.close();
      }
    } finally {
      client.close();
    }

    if (await targetFile.length() == 0) {
      await targetFile.delete();
      throw Exception('Arquivo baixado está vazio. Tente novamente.');
    }

    return targetFile;
  }

  String getFriendlyError(String code) {
    switch (code) {
      case 'PERMISSION_DENIED':
        return 'Acesso negado. Configure o arquivo como público no Drive.';
      case 'NOT_FOUND':
        return 'Arquivo não encontrado. Verifique o link.';
      case 'FOLDER_NO_API':
        return 'Pastas públicas precisam de API key. Adicione arquivos individuais.';
      default:
        return 'Erro ao acessar o arquivo. Verifique o link e tente novamente.';
    }
  }
}
