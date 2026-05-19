import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../../../core/storage/saf_file_resolver.dart';
import '../../library/domain/library_item.dart';
import 'ebook_format_support.dart';

class BookTextSegment {
  final String title;
  final String text;

  const BookTextSegment({required this.title, required this.text});
}

class BookTextExtractionResult {
  final List<BookTextSegment> segments;
  final String sourceLabel;

  const BookTextExtractionResult({
    required this.segments,
    required this.sourceLabel,
  });
}

class BookTextExtractor {
  static const int _maxSegmentLength = 2800;

  Future<BookTextExtractionResult> extract(LibraryItem item) async {
    switch (item.type) {
      case ItemType.text:
        return _extractTextFile(item);
      case ItemType.ebook:
        if (!EbookFormatSupport.canReadInternally(item)) {
          throw const BookTextExtractionException(
            'Este ebook ainda precisa ser convertido para EPUB antes do TTS.',
          );
        }
        return _extractEpub(item);
      case ItemType.pdf:
        return _extractPdf(item);
      case ItemType.document:
        throw const BookTextExtractionException(
          'DOC e DOCX ainda precisam de leitor/conversor antes do TTS.',
        );
      case ItemType.hq:
        throw const BookTextExtractionException(
          'HQ/Manga ainda precisa de OCR por pagina antes do TTS.',
        );
      case ItemType.audio:
        throw const BookTextExtractionException(
          'Arquivos de audio ja abrem no player de audiobook.',
        );
    }
  }

  Future<BookTextExtractionResult> _extractTextFile(LibraryItem item) async {
    final bytes = await _readItemBytes(item);
    final text = utf8.decode(bytes, allowMalformed: true);
    final segments = _splitText(text, titlePrefix: 'Texto');
    return _nonEmptyResult(segments, 'TXT');
  }

  Future<BookTextExtractionResult> _extractEpub(LibraryItem item) async {
    final bytes = await _readItemBytes(item);
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = {
      for (final file in archive.files) _normalizeZipPath(file.name): file,
    };

    final opfPath = _findOpfPath(files);
    final spinePaths = opfPath == null
        ? const <String>[]
        : _findSpinePaths(files, opfPath);

    final contentPaths = spinePaths.isNotEmpty
        ? List<String>.of(spinePaths)
        : (files.keys
              .where((path) => _isReadableEpubContent(path))
              .where((path) => !path.toLowerCase().contains('nav.'))
              .where((path) => !path.toLowerCase().contains('toc.'))
              .toList()
            ..sort());

    final segments = <BookTextSegment>[];
    for (var i = 0; i < contentPaths.length; i++) {
      final file = files[contentPaths[i]];
      if (file == null || !file.isFile) continue;

      final html = utf8.decode(file.content, allowMalformed: true);
      final text = _htmlToText(html);
      segments.addAll(_splitText(text, titlePrefix: 'Capitulo ${i + 1}'));
    }

    return _nonEmptyResult(segments, 'EPUB');
  }

  Future<BookTextExtractionResult> _extractPdf(LibraryItem item) async {
    PdfDocument? document;
    try {
      final localPath = item.localPath?.trim();
      final remoteUrl = item.remoteUrl?.trim();
      if (localPath != null && localPath.isNotEmpty) {
        final file = await SafFileResolver.resolveForProcessing(localPath);
        document = await PdfDocument.openFile(file.path);
      } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
        document = await PdfDocument.openUri(Uri.parse(remoteUrl));
      } else {
        throw const BookTextExtractionException('Arquivo PDF nao disponivel.');
      }

      final segments = <BookTextSegment>[];
      for (final page in document.pages) {
        final pageText = await page.loadStructuredText();
        segments.addAll(
          _splitText(
            pageText.fullText,
            titlePrefix: 'Pagina ${page.pageNumber}',
          ),
        );
      }

      return _nonEmptyResult(
        segments,
        'PDF',
        emptyMessage:
            'Nao encontrei texto selecionavel neste PDF. Para PDF escaneado, precisa OCR antes do TTS.',
      );
    } finally {
      await document?.dispose();
    }
  }

  Future<Uint8List> _readItemBytes(LibraryItem item) async {
    final localPath = item.localPath?.trim();
    final remoteUrl = item.remoteUrl?.trim();

    if (localPath != null && localPath.isNotEmpty) {
      final file = await SafFileResolver.resolveForProcessing(localPath);
      return file.readAsBytes();
    }

    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      final response = await http.get(Uri.parse(remoteUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BookTextExtractionException(
          'Nao foi possivel baixar o arquivo para TTS (${response.statusCode}).',
        );
      }
      return response.bodyBytes;
    }

    throw const BookTextExtractionException('Arquivo nao disponivel.');
  }

  String? _findOpfPath(Map<String, ArchiveFile> files) {
    final container = _findArchiveFile(files, 'META-INF/container.xml');
    if (container != null && container.isFile) {
      try {
        final xml = XmlDocument.parse(
          utf8.decode(container.content, allowMalformed: true),
        );
        final rootFile = xml
            .findAllElements('rootfile')
            .map((node) => node.getAttribute('full-path'))
            .firstWhere(
              (path) => path != null && path.trim().isNotEmpty,
              orElse: () => null,
            );
        if (rootFile != null) return _normalizeZipPath(rootFile);
      } catch (_) {
        // Fallback abaixo tenta achar qualquer OPF.
      }
    }

    final opfFiles =
        files.keys.where((path) => path.toLowerCase().endsWith('.opf')).toList()
          ..sort();
    return opfFiles.isEmpty ? null : opfFiles.first;
  }

  ArchiveFile? _findArchiveFile(Map<String, ArchiveFile> files, String path) {
    final exact = files[path];
    if (exact != null) return exact;

    final lower = path.toLowerCase();
    for (final entry in files.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  List<String> _findSpinePaths(Map<String, ArchiveFile> files, String opfPath) {
    final opfFile = files[opfPath];
    if (opfFile == null || !opfFile.isFile) return const [];

    try {
      final xml = XmlDocument.parse(
        utf8.decode(opfFile.content, allowMalformed: true),
      );
      final manifest = <String, String>{};
      for (final item in xml.findAllElements('item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        if (id == null || href == null || href.trim().isEmpty) continue;
        manifest[id] = _joinZipPath(p.url.dirname(opfPath), href);
      }

      final paths = <String>[];
      for (final itemref in xml.findAllElements('itemref')) {
        final idref = itemref.getAttribute('idref');
        final path = idref == null ? null : manifest[idref];
        if (path != null && _isReadableEpubContent(path)) {
          paths.add(path);
        }
      }
      return paths;
    } catch (_) {
      return const [];
    }
  }

  BookTextExtractionResult _nonEmptyResult(
    List<BookTextSegment> segments,
    String sourceLabel, {
    String emptyMessage = 'Nao encontrei texto para ler por voz neste arquivo.',
  }) {
    final cleanSegments = segments
        .where((segment) => segment.text.trim().length >= 2)
        .toList(growable: false);
    if (cleanSegments.isEmpty) {
      throw BookTextExtractionException(emptyMessage);
    }
    return BookTextExtractionResult(
      segments: cleanSegments,
      sourceLabel: sourceLabel,
    );
  }

  List<BookTextSegment> _splitText(String text, {required String titlePrefix}) {
    final normalized = text
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (normalized.isEmpty) return const [];

    final parts = normalized
        .split(RegExp(r'\n\s*\n'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    final segments = <BookTextSegment>[];
    final buffer = StringBuffer();

    void flush() {
      final value = buffer.toString().trim();
      if (value.isEmpty) return;
      segments.add(
        BookTextSegment(
          title: segments.isEmpty
              ? titlePrefix
              : '$titlePrefix.${segments.length + 1}',
          text: value,
        ),
      );
      buffer.clear();
    }

    for (final part in parts) {
      if (part.length > _maxSegmentLength) {
        flush();
        for (final chunk in _splitLongParagraph(part)) {
          segments.add(
            BookTextSegment(
              title: segments.isEmpty
                  ? titlePrefix
                  : '$titlePrefix.${segments.length + 1}',
              text: chunk,
            ),
          );
        }
        continue;
      }

      if (buffer.length + part.length + 2 > _maxSegmentLength) {
        flush();
      }
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(part);
    }
    flush();

    return segments;
  }

  List<String> _splitLongParagraph(String paragraph) {
    final sentences = RegExp(r'[^.!?]+[.!?]*\s*')
        .allMatches(paragraph)
        .map((match) => match.group(0)?.trim() ?? '')
        .where((sentence) => sentence.isNotEmpty);
    final chunks = <String>[];
    final buffer = StringBuffer();

    for (final sentence in sentences) {
      if (sentence.length > _maxSegmentLength) {
        if (buffer.isNotEmpty) {
          chunks.add(buffer.toString().trim());
          buffer.clear();
        }
        for (var i = 0; i < sentence.length; i += _maxSegmentLength) {
          chunks.add(
            sentence
                .substring(i, (i + _maxSegmentLength).clamp(0, sentence.length))
                .trim(),
          );
        }
        continue;
      }

      if (buffer.length + sentence.length + 1 > _maxSegmentLength) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
    }

    if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
    return chunks.where((chunk) => chunk.isNotEmpty).toList();
  }

  String _htmlToText(String html) {
    final document = html_parser.parse(html);
    document.querySelectorAll('script, style, svg').forEach((node) {
      node.remove();
    });
    return document.body?.text.trim() ??
        document.documentElement?.text.trim() ??
        '';
  }

  bool _isReadableEpubContent(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm');
  }

  String _joinZipPath(String base, String href) {
    final cleanedHref = href.split('#').first;
    if (base == '.' || base.isEmpty) return _normalizeZipPath(cleanedHref);
    return _normalizeZipPath(p.url.normalize(p.url.join(base, cleanedHref)));
  }

  String _normalizeZipPath(String value) {
    return p.url
        .normalize(value.replaceAll('\\', '/'))
        .replaceFirst(RegExp(r'^/'), '');
  }
}

class BookTextExtractionException implements Exception {
  final String message;

  const BookTextExtractionException(this.message);

  @override
  String toString() => message;
}
