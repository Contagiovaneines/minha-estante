import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'native_archive_service.dart';

class CbrToCbzConverterService {
  static const _imageExts = ['.jpg', '.jpeg', '.png', '.webp', '.gif'];
  static const _archiveExts = ['.cbr', '.rar', '.cbz', '.zip'];
  static const _maxImages = 2000;
  static const _maxBytes = 1024 * 1024 * 1024; // 1 GB

  static const _ignoredNames = [
    '__macosx',
    '.ds_store',
    'thumbs.db',
    'desktop.ini',
  ];

  Future<File> convertCbrToCbz(File cbrFile) {
    return convertPathOrUriToCbz(
      cbrFile.path,
      displayName: p.basename(cbrFile.path),
    );
  }

  /// Converte um CBR/RAR local ou content:// para CBZ no cache interno.
  Future<File> convertPathOrUriToCbz(
    String pathOrUri, {
    String? displayName,
  }) async {
    final isContentUri = pathOrUri.startsWith('content://');
    File? localFile;
    File? fallbackFile;
    FileStat? stat;

    final ext = p.extension(displayName ?? pathOrUri).toLowerCase();
    if (ext.isNotEmpty && !_archiveExts.contains(ext)) {
      throw Exception(
        'Arquivo inválido. Apenas CBR, RAR e CBZ são suportados.',
      );
    }

    if (!isContentUri) {
      localFile = File(pathOrUri);
      if (!await localFile.exists()) {
        throw Exception('Arquivo CBR não encontrado no dispositivo.');
      }
      stat = await localFile.stat();
      if (stat.size <= 0) {
        throw Exception('Arquivo CBR vazio ou inválido.');
      }
      if (stat.size > _maxBytes) {
        throw Exception('Este CBR excede o limite de 1 GB.');
      }
    }

    final hashInput = isContentUri
        ? '${pathOrUri}_${displayName ?? ''}'
        : '${localFile!.path}_${stat!.size}_${stat.modified.millisecondsSinceEpoch}';
    final hash = sha1
        .convert(utf8.encode(hashInput))
        .toString()
        .substring(0, 16);

    final appCacheDir = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(appCacheDir.path, 'cbr_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final cbzFile = File(p.join(cacheDir.path, 'converted_$hash.cbz'));
    if (await cbzFile.exists()) {
      return cbzFile;
    }

    final nativeService = NativeArchiveService();
    var nativeMessage = '';

    try {
      try {
        final tempNativeCbz = await nativeService.convertCbrToCbz(pathOrUri);
        await _moveWithoutOverwrite(tempNativeCbz, cbzFile);
        return cbzFile;
      } catch (e) {
        nativeMessage = e.toString();
      }

      if (_isPasswordError(nativeMessage)) {
        throw Exception(
          'Este CBR está protegido por senha e não pode ser convertido.',
        );
      }

      try {
        fallbackFile = localFile;
        if (isContentUri) {
          fallbackFile = await nativeService.copyArchiveUriToCache(pathOrUri);
        }

        await _convertRenamedZipToCbz(fallbackFile!, cbzFile);
        return cbzFile;
      } catch (_) {
        if (_isPasswordError(nativeMessage)) {
          throw Exception(
            'Este CBR está protegido por senha e não pode ser convertido.',
          );
        }
        if (nativeMessage.contains('Nenhuma imagem compatível')) {
          throw Exception('Nenhuma imagem compatível foi encontrada no CBR.');
        }
        throw Exception(
          'Não foi possível converter este CBR. Tente converter manualmente para CBZ.',
        );
      }
    } catch (e) {
      if (await cbzFile.exists()) await cbzFile.delete();
      rethrow;
    }
  }

  Future<void> _moveWithoutOverwrite(File source, File target) async {
    if (await target.exists()) {
      throw Exception('Arquivo convertido já existe no cache.');
    }
    try {
      await source.rename(target.path);
    } on FileSystemException {
      await source.copy(target.path);
      await source.delete();
    }
  }

  Future<void> _convertRenamedZipToCbz(File source, File output) async {
    if (!await source.exists()) {
      throw Exception('Arquivo CBR não encontrado no dispositivo.');
    }

    final stat = await source.stat();
    if (stat.size <= 0) {
      throw Exception('Arquivo CBR vazio ou inválido.');
    }
    if (stat.size > _maxBytes) {
      throw Exception('Este CBR excede o limite de 1 GB.');
    }

    ZipFileEncoder? encoder;
    var encoderCreated = false;
    final input = InputFileStream(source.path);

    try {
      final archive = ZipDecoder().decodeStream(input);
      final images = archive.files.where((file) {
        if (!file.isFile) return false;
        final normalized = _normalizeArchiveName(file.name);
        if (_isUnsafeArchiveName(normalized)) return false;
        if (_isIgnoredArchiveName(normalized)) return false;
        return _isImageName(normalized);
      }).toList()..sort((a, b) => _naturalCompare(a.name, b.name));

      if (images.isEmpty) {
        throw Exception('Nenhuma imagem compatível foi encontrada no CBR.');
      }

      encoder = ZipFileEncoder();
      encoder.create(output.path);
      encoderCreated = true;

      var imageCount = 0;
      var totalBytes = 0;
      for (final image in images) {
        if (imageCount >= _maxImages) {
          throw Exception('Este CBR excede o limite de $_maxImages páginas.');
        }
        totalBytes += image.size;
        if (totalBytes > _maxBytes) {
          throw Exception('Este CBR excede o limite de 1 GB.');
        }

        final rawContent = image.rawContent;
        if (rawContent == null) continue;

        imageCount += 1;
        final entry =
            ArchiveFile.file(
                _safeZipEntryName(image.name, imageCount),
                image.size,
                rawContent,
              )
              ..crc32 = image.crc32
              ..compression = image.compression
              ..lastModTime = image.lastModTime;
        encoder.addArchiveFile(entry);
      }

      if (imageCount == 0) {
        throw Exception('Nenhuma imagem compatível foi encontrada no CBR.');
      }

      await encoder.close();
      encoderCreated = false;
    } catch (_) {
      if (encoderCreated) {
        encoder?.closeSync();
      }
      if (await output.exists()) {
        await output.delete();
      }
      rethrow;
    } finally {
      input.closeSync();
    }
  }

  bool _isPasswordError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('senha') ||
        lower.contains('password') ||
        lower.contains('protected') ||
        lower.contains('encrypted');
  }

  static String _normalizeArchiveName(String name) {
    return name.replaceAll('\\', '/').trim();
  }

  static bool _isUnsafeArchiveName(String name) {
    final normalized = _normalizeArchiveName(name);
    if (normalized.startsWith('/')) return true;
    if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return true;
    return normalized.split('/').any((segment) => segment == '..');
  }

  static bool _isIgnoredArchiveName(String name) {
    final normalized = _normalizeArchiveName(name).toLowerCase();
    final parts = normalized.split('/');
    final leaf = parts.isEmpty ? '' : parts.last;
    return parts.contains('__macosx') || _ignoredNames.contains(leaf);
  }

  static bool _isImageName(String name) {
    final normalized = _normalizeArchiveName(name).toLowerCase();
    return _imageExts.any((ext) => normalized.endsWith(ext));
  }

  static String _safeZipEntryName(String name, int index) {
    final leaf = _normalizeArchiveName(name).split('/').last;
    final safeLeaf = leaf.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final paddedIndex = index.toString().padLeft(4, '0');
    return '${paddedIndex}_${safeLeaf.isEmpty ? 'page' : safeLeaf}';
  }

  static int _naturalCompare(String a, String b) {
    final regex = RegExp(r'(\d+)');
    final ma = regex.allMatches(a).toList();
    final mb = regex.allMatches(b).toList();
    for (var i = 0; i < ma.length && i < mb.length; i++) {
      final na = int.parse(ma[i].group(0)!);
      final nb = int.parse(mb[i].group(0)!);
      if (na != nb) return na.compareTo(nb);
    }
    return a.compareTo(b);
  }
}
