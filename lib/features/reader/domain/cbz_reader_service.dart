import 'dart:io';
import 'dart:async';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class CbzReaderService {
  static const _imageExts = [
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.jfif',
    '.avif',
    '.gif',
    '.bmp',
  ];

  /// Retorna as imagens extraídas do CBZ ordenadas naturalmente
  Future<List<File>> extractCbz(String cbzPath, String id) async {
    final tempDir = await getTemporaryDirectory();
    final extractPath = '${tempDir.path}/hq_extract_$id';
    final extractDir = Directory(extractPath);

    if (await extractDir.exists()) {
      await extractDir.delete(recursive: true);
    }
    await extractDir.create(recursive: true);

    // Passamos o caminho (String) em vez dos bytes para economizar centenas de MB de RAM
    return compute(_extractTask, {
      'cbzPath': cbzPath,
      'extractPath': extractPath,
    });
  }

  static Future<List<File>> _extractTask(Map<String, dynamic> params) async {
    final String cbzPath = params['cbzPath'];
    final String extractPath = params['extractPath'];
    final extractedFiles = <File>[];

    final input = InputFileStream(cbzPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      int totalFiles = archive.files.length;

      for (final file in archive.files) {
        if (!file.isFile) continue;
        final normalizedName = file.name.replaceAll('\\', '/').trim();
        final lowerName = normalizedName.toLowerCase();

        if (lowerName.startsWith('/') ||
            RegExp(r'^[a-z]:').hasMatch(lowerName) ||
            lowerName.split('/').contains('..') ||
            lowerName.split('/').contains('__macosx') ||
            lowerName.endsWith('/.ds_store') ||
            lowerName.endsWith('/thumbs.db')) {
          continue;
        }

        if (!_imageExts.any((ext) => lowerName.endsWith(ext))) continue;

        final outputPath =
            '$extractPath/${normalizedName.replaceAll('/', '_')}';
        final outputFile = File(outputPath);
        final output = OutputFileStream(outputFile.path);
        try {
          file.writeContent(output);
        } finally {
          output.closeSync();
        }

        if (outputFile.lengthSync() <= 0 ||
            !_hasSupportedImageSignature(outputFile)) {
          outputFile.deleteSync();
          continue;
        }

        extractedFiles.add(outputFile);
      }

      if (extractedFiles.isEmpty) {
        throw Exception(
          'Nenhuma imagem suportada encontrada. '
          'O arquivo contém $totalFiles item(s), mas nenhum é uma imagem válida (.jpg, .png, etc).',
        );
      }
    } finally {
      input.closeSync();
    }

    // Ordenação natural para garantir a ordem das páginas
    extractedFiles.sort((a, b) => _naturalCompare(a.path, b.path));

    return extractedFiles;
  }

  static bool _hasSupportedImageSignature(File file) {
    final bytes = file.openSync();
    try {
      final length = file.lengthSync();
      final header = bytes.readSync(length < 16 ? length : 16);
      if (header.length < 4) return false;

      final isJpeg =
          header.length >= 3 &&
          header[0] == 0xff &&
          header[1] == 0xd8 &&
          header[2] == 0xff;
      final isPng =
          header.length >= 8 &&
          header[0] == 0x89 &&
          header[1] == 0x50 &&
          header[2] == 0x4e &&
          header[3] == 0x47 &&
          header[4] == 0x0d &&
          header[5] == 0x0a &&
          header[6] == 0x1a &&
          header[7] == 0x0a;
      final isGif =
          header.length >= 6 &&
          header[0] == 0x47 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x38 &&
          (header[4] == 0x37 || header[4] == 0x39) &&
          header[5] == 0x61;
      final isWebp =
          header.length >= 12 &&
          header[0] == 0x52 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x46 &&
          header[8] == 0x57 &&
          header[9] == 0x45 &&
          header[10] == 0x42 &&
          header[11] == 0x50;
      final isBmp = header[0] == 0x42 && header[1] == 0x4d;
      final isAvif =
          header.length >= 12 &&
          header[4] == 0x66 &&
          header[5] == 0x74 &&
          header[6] == 0x79 &&
          header[7] == 0x70 &&
          header[8] == 0x61 &&
          header[9] == 0x76 &&
          header[10] == 0x69 &&
          header[11] == 0x66;

      return isJpeg || isPng || isGif || isWebp || isBmp || isAvif;
    } finally {
      bytes.closeSync();
    }
  }

  Future<void> cleanup(String id) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final extractDir = Directory('${tempDir.path}/hq_extract_$id');
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  static int _naturalCompare(String a, String b) {
    final regex = RegExp(r'(\d+)');
    final matchesA = regex.allMatches(a).toList();
    final matchesB = regex.allMatches(b).toList();

    var i = 0;
    while (i < matchesA.length && i < matchesB.length) {
      final numA = int.parse(matchesA[i].group(0)!);
      final numB = int.parse(matchesB[i].group(0)!);

      if (numA != numB) {
        return numA.compareTo(numB);
      }
      i++;
    }
    return a.compareTo(b);
  }
}
