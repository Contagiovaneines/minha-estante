import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/library_item.dart';

const _cbzCoverImageExts = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

Future<String?> _extractFirstCbzCover(Map<String, String> params) async {
  final cbzPath = params['cbzPath']!;
  final cachePath = params['cachePath']!;
  final input = InputFileStream(cbzPath);

  try {
    final archive = ZipDecoder().decodeStream(input);
    final imageFiles = archive.files.where(_isSafeCoverEntry).toList()
      ..sort((a, b) => _naturalCompare(a.name, b.name));

    if (imageFiles.isEmpty) return null;

    final outputFile = File(cachePath);
    if (!outputFile.parent.existsSync()) {
      outputFile.parent.createSync(recursive: true);
    }

    final output = OutputFileStream(outputFile.path);
    try {
      imageFiles.first.writeContent(output);
    } finally {
      output.closeSync();
    }

    if (outputFile.lengthSync() <= 0 ||
        !_hasSupportedImageSignature(outputFile)) {
      outputFile.deleteSync();
      return null;
    }

    return outputFile.path;
  } catch (_) {
    return null;
  } finally {
    input.closeSync();
  }
}

bool _isSafeCoverEntry(ArchiveFile file) {
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

  return _cbzCoverImageExts.contains(p.extension(fileName));
}

bool _hasSupportedImageSignature(File file) {
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

    return isJpeg || isPng || isGif || isWebp;
  } finally {
    bytes.closeSync();
  }
}

int _naturalCompare(String a, String b) {
  final regex = RegExp(r'(\d+)');
  final matchesA = regex.allMatches(a).toList();
  final matchesB = regex.allMatches(b).toList();

  var index = 0;
  while (index < matchesA.length && index < matchesB.length) {
    final numA = int.parse(matchesA[index].group(0)!);
    final numB = int.parse(matchesB[index].group(0)!);
    if (numA != numB) return numA.compareTo(numB);
    index++;
  }

  return a.compareTo(b);
}

class LibraryItemCover extends StatelessWidget {
  final LibraryItem item;
  final BorderRadius borderRadius;
  final double iconSize;

  const LibraryItemCover({
    super.key,
    required this.item,
    required this.borderRadius,
    this.iconSize = 52,
  });

  @override
  Widget build(BuildContext context) {
    final coverColor = _coverColor(context);

    return ClipRRect(
      borderRadius: borderRadius,
      child: ColoredBox(
        color: coverColor.withValues(alpha: 0.12),
        child: _buildCoverContent(context),
      ),
    );
  }

  Widget _buildCoverContent(BuildContext context) {
    final thumbnailUrl = item.thumbnailUrl;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      final uri = Uri.tryParse(thumbnailUrl);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return Image.network(
          thumbnailUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildGeneratedCover(context),
        );
      }

      return Image.file(
        File(thumbnailUrl),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _buildGeneratedCover(context),
      );
    }

    if (item.type == ItemType.pdf && item.localPath != null) {
      return _buildPdfPreview(
        context,
        PdfDocumentViewBuilder.file(
          item.localPath!,
          loadingBuilder: (_) => _buildGeneratedCover(context),
          errorBuilder: (_, _, _) => _buildGeneratedCover(context),
          builder: _buildPdfPage,
        ),
      );
    }

    if (item.type == ItemType.pdf && item.remoteUrl != null) {
      return _buildPdfPreview(
        context,
        PdfDocumentViewBuilder.uri(
          Uri.parse(item.remoteUrl!),
          loadingBuilder: (_) => _buildGeneratedCover(context),
          errorBuilder: (_, _, _) => _buildGeneratedCover(context),
          builder: _buildPdfPage,
        ),
      );
    }

    if (_hasLocalCbzCover) {
      return _CbzCoverPreview(
        item: item,
        fallback: _buildGeneratedCover(context),
      );
    }

    return _buildGeneratedCover(context);
  }

  bool get _hasLocalCbzCover {
    final path = item.localPath;
    if (item.type != ItemType.hq ||
        path == null ||
        path.startsWith('content://')) {
      return false;
    }

    final lowerPath = path.toLowerCase();
    return lowerPath.endsWith('.cbz') || lowerPath.endsWith('.zip');
  }

  Widget _buildPdfPreview(BuildContext context, Widget child) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            colors.surfaceContainerHighest.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(8), child: child),
    );
  }

  Widget _buildPdfPage(BuildContext context, PdfDocument? document) {
    if (document == null || document.pages.isEmpty) {
      return _buildGeneratedCover(context);
    }

    return PdfPageView(
      document: document,
      pageNumber: 1,
      maximumDpi: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      backgroundColor: Colors.white,
    );
  }

  Widget _buildGeneratedCover(BuildContext context) {
    final coverColor = _coverColor(context);

    return Center(
      child: Icon(
        _coverIcon,
        size: iconSize,
        color: coverColor.withValues(alpha: 0.72),
      ),
    );
  }

  Color _coverColor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    switch (item.type) {
      case ItemType.pdf:
        return colors.primary;
      case ItemType.hq:
        return AppColors.comicAccent;
      case ItemType.audio:
        return AppColors.audioAccent;
      case ItemType.ebook:
        return colors.primaryContainer;
      case ItemType.document:
        return AppColors.localAccent;
      case ItemType.text:
        return colors.onSurfaceVariant;
    }
  }

  IconData get _coverIcon {
    switch (item.type) {
      case ItemType.pdf:
        return Icons.picture_as_pdf_rounded;
      case ItemType.hq:
        return Icons.auto_stories_rounded;
      case ItemType.audio:
        return Icons.headphones_rounded;
      case ItemType.ebook:
        return Icons.menu_book_rounded;
      case ItemType.document:
        return Icons.description_rounded;
      case ItemType.text:
        return Icons.article_rounded;
    }
  }
}

class _CbzCoverPreview extends StatefulWidget {
  final LibraryItem item;
  final Widget fallback;

  const _CbzCoverPreview({required this.item, required this.fallback});

  @override
  State<_CbzCoverPreview> createState() => _CbzCoverPreviewState();
}

class _CbzCoverPreviewState extends State<_CbzCoverPreview> {
  late Future<File?> _coverFuture;

  @override
  void initState() {
    super.initState();
    _coverFuture = _loadCover();
  }

  @override
  void didUpdateWidget(covariant _CbzCoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.localPath != widget.item.localPath) {
      _coverFuture = _loadCover();
    }
  }

  Future<File?> _loadCover() async {
    final cbzPath = widget.item.localPath;
    if (cbzPath == null) return null;

    final sourceFile = File(cbzPath);
    if (!await sourceFile.exists()) return null;

    final tempDir = await getTemporaryDirectory();
    final safeId = widget.item.id.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final cacheFile = File(
      p.join(tempDir.path, 'cover_cache', '$safeId.cover'),
    );
    if (await cacheFile.exists() && await cacheFile.length() > 0) {
      return cacheFile;
    }

    final coverPath = await compute(_extractFirstCbzCover, {
      'cbzPath': sourceFile.path,
      'cachePath': cacheFile.path,
    });
    if (coverPath == null) return null;

    final coverFile = File(coverPath);
    return await coverFile.exists() ? coverFile : null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _coverFuture,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return widget.fallback;

        return Image.file(
          file,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => widget.fallback,
        );
      },
    );
  }
}
