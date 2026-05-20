import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import 'library_item.dart';

const _coverImageExts = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

class LibraryMetadata {
  final String? title;
  final String? author;
  final String? description;
  final String? thumbnailPath;
  final int? totalPages;
  final int? durationSeconds;

  const LibraryMetadata({
    this.title,
    this.author,
    this.description,
    this.thumbnailPath,
    this.totalPages,
    this.durationSeconds,
  });

  bool get isEmpty =>
      title == null &&
      author == null &&
      description == null &&
      thumbnailPath == null &&
      totalPages == null &&
      durationSeconds == null;

  LibraryItem applyTo(LibraryItem item) {
    var updated = item;

    if (_hasText(title)) {
      updated = updated.copyWith(title: title!.trim());
    }
    if (!_hasText(updated.author) && _hasText(author)) {
      updated = updated.copyWith(author: author!.trim());
    }
    if (!_hasText(updated.description) && _hasText(description)) {
      updated = updated.copyWith(description: description!.trim());
    }
    if (!_hasText(updated.thumbnailUrl) && _hasText(thumbnailPath)) {
      updated = updated.copyWith(thumbnailUrl: thumbnailPath!.trim());
    }
    if (updated.totalPages <= 0 && (totalPages ?? 0) > 0) {
      updated = updated.copyWith(totalPages: totalPages);
    }
    if (updated.durationSeconds == null && (durationSeconds ?? 0) > 0) {
      updated = updated.copyWith(durationSeconds: durationSeconds);
    }

    return updated;
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

class LibraryMetadataService {
  static const MethodChannel _channel = MethodChannel(
    'minha_estante/file_metadata',
  );

  Future<LibraryItem> enrich(LibraryItem item) async {
    final path = item.localPath;
    if (path == null || path.trim().isEmpty || path.startsWith('content://')) {
      return item;
    }

    final file = File(path);
    if (!await file.exists()) return item;

    var metadata = const LibraryMetadata();
    switch (item.type) {
      case ItemType.pdf:
        metadata = await _readNativeMetadata(item);
      case ItemType.audio:
        metadata = await _readNativeMetadata(item);
      case ItemType.ebook:
        metadata = await _readEpubMetadata(item);
      case ItemType.hq:
        metadata = await _readComicMetadata(item);
      case ItemType.document:
      case ItemType.text:
        metadata = const LibraryMetadata();
    }

    if (metadata.isEmpty) return item;
    return metadata.applyTo(item).copyWith(updatedAt: DateTime.now());
  }

  Future<LibraryMetadata> _readNativeMetadata(LibraryItem item) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const LibraryMetadata();
    }

    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'extractFileMetadata',
        {'path': item.localPath, 'itemId': item.id, 'type': item.type.name},
      );
      if (raw == null) return const LibraryMetadata();

      return LibraryMetadata(
        title: _cleanText(raw['title']),
        author: _cleanText(raw['author']),
        thumbnailPath: _cleanText(raw['thumbnailPath']),
        totalPages: _cleanPositiveInt(raw['totalPages']),
        durationSeconds: _cleanPositiveInt(raw['durationSeconds']),
      );
    } catch (_) {
      return const LibraryMetadata();
    }
  }

  Future<LibraryMetadata> _readComicMetadata(LibraryItem item) async {
    final path = item.localPath;
    if (path == null) return const LibraryMetadata();

    final lowerPath = path.toLowerCase();
    if (!lowerPath.endsWith('.cbz') && !lowerPath.endsWith('.zip')) {
      return const LibraryMetadata();
    }

    InputFileStream? input;
    try {
      input = InputFileStream(path);
      final archive = ZipDecoder().decodeStream(input);
      final pageCount = archive.files.where(_isSafeImageEntry).length;
      return LibraryMetadata(totalPages: pageCount > 0 ? pageCount : null);
    } catch (_) {
      return const LibraryMetadata();
    } finally {
      input?.closeSync();
    }
  }

  Future<LibraryMetadata> _readEpubMetadata(LibraryItem item) async {
    final path = item.localPath;
    if (path == null || !path.toLowerCase().endsWith('.epub')) {
      return const LibraryMetadata();
    }

    InputFileStream? input;
    try {
      input = InputFileStream(path);
      final archive = ZipDecoder().decodeStream(input);
      final container = _archiveFile(archive, 'META-INF/container.xml');
      if (container == null) return const LibraryMetadata();

      final containerXml = XmlDocument.parse(_decodeUtf8(container.content));
      final rootPath = containerXml
          .findAllElements('rootfile', namespace: '*')
          .map((node) => node.getAttribute('full-path'))
          .whereType<String>()
          .firstOrNull;
      if (rootPath == null || rootPath.trim().isEmpty) {
        return const LibraryMetadata();
      }

      final opf = _archiveFile(archive, rootPath);
      if (opf == null) return const LibraryMetadata();

      final opfXml = XmlDocument.parse(_decodeUtf8(opf.content));
      final coverPath = await _extractEpubCover(
        archive: archive,
        opfXml: opfXml,
        opfPath: rootPath,
        itemId: item.id,
      );

      return LibraryMetadata(
        title: _firstXmlText(opfXml, 'title'),
        author: _firstXmlText(opfXml, 'creator'),
        description: _firstXmlText(opfXml, 'description'),
        thumbnailPath: coverPath,
      );
    } catch (_) {
      return const LibraryMetadata();
    } finally {
      input?.closeSync();
    }
  }

  Future<String?> _extractEpubCover({
    required Archive archive,
    required XmlDocument opfXml,
    required String opfPath,
    required String itemId,
  }) async {
    final manifestItems = opfXml.findAllElements('item', namespace: '*');
    XmlElement? coverItem;

    for (final item in manifestItems) {
      final properties = item.getAttribute('properties') ?? '';
      if (properties.split(RegExp(r'\s+')).contains('cover-image')) {
        coverItem = item;
        break;
      }
    }

    if (coverItem == null) {
      final coverId = opfXml
          .findAllElements('meta', namespace: '*')
          .where((node) => node.getAttribute('name') == 'cover')
          .map((node) => node.getAttribute('content'))
          .whereType<String>()
          .firstOrNull;
      if (coverId != null) {
        for (final item in manifestItems) {
          if (item.getAttribute('id') == coverId) {
            coverItem = item;
            break;
          }
        }
      }
    }

    final href = coverItem?.getAttribute('href');
    if (href == null || href.trim().isEmpty) return null;

    final coverArchivePath = p.posix.normalize(
      p.posix.join(p.posix.dirname(opfPath), Uri.decodeFull(href)),
    );
    if (!_looksLikeImagePath(coverArchivePath)) return null;

    final coverArchiveFile = _archiveFile(archive, coverArchivePath);
    if (coverArchiveFile == null || !coverArchiveFile.isFile) return null;

    final supportDir = await getApplicationSupportDirectory();
    final coverDir = Directory(p.join(supportDir.path, 'metadata_covers'));
    if (!await coverDir.exists()) {
      await coverDir.create(recursive: true);
    }

    final safeId = itemId.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final ext = p.extension(coverArchivePath).toLowerCase();
    final output = File(p.join(coverDir.path, '$safeId$ext'));
    await output.writeAsBytes(coverArchiveFile.content, flush: true);
    return output.path;
  }

  static ArchiveFile? _archiveFile(Archive archive, String path) {
    final normalizedPath = path.replaceAll('\\', '/').toLowerCase();
    for (final file in archive.files) {
      if (file.name.replaceAll('\\', '/').toLowerCase() == normalizedPath) {
        return file;
      }
    }
    return null;
  }

  static bool _isSafeImageEntry(ArchiveFile file) {
    if (!file.isFile) return false;

    final normalizedName = file.name.replaceAll('\\', '/').trim();
    if (normalizedName.isEmpty) return false;

    final lowerName = normalizedName.toLowerCase();
    final segments = lowerName.split('/');
    final fileName = segments.last;

    if (lowerName.startsWith('/') ||
        RegExp(r'^[a-z]:').hasMatch(lowerName) ||
        segments.contains('..') ||
        segments.contains('__macosx') ||
        fileName == '.ds_store' ||
        fileName == 'thumbs.db') {
      return false;
    }

    return _looksLikeImagePath(fileName);
  }

  static bool _looksLikeImagePath(String path) {
    return _coverImageExts.contains(p.extension(path).toLowerCase());
  }

  static String _decodeUtf8(Uint8List bytes) {
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String? _firstXmlText(XmlDocument document, String localName) {
    for (final element in document.findAllElements(localName, namespace: '*')) {
      final value = _cleanText(element.innerText);
      if (value != null) return value;
    }
    return null;
  }

  static String? _cleanText(Object? value) {
    if (value == null) return null;
    final text = value
        .toString()
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return null;
    if (text.toLowerCase() == 'unknown') return null;
    return text;
  }

  static int? _cleanPositiveInt(Object? value) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed != null && parsed > 0 ? parsed : null;
    }
    return null;
  }
}
