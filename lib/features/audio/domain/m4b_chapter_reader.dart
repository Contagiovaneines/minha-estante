import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Representa um capitulo de um arquivo M4B.
class M4bChapter {
  final int index;
  final String title;
  final Duration start;
  final Duration? end;

  const M4bChapter({
    required this.index,
    required this.title,
    required this.start,
    this.end,
  });

  String get formattedStart {
    final h = start.inHours;
    final m = start.inMinutes % 60;
    final s = start.inSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Le capitulos de arquivos M4B/M4A via parsing dos atomos ISO Base Media.
///
/// Suporta `chpl` e capitulos QuickTime por trilha de texto referenciada pelo
/// atomo `chap` em `trak/tref/chap`.
class M4bChapterReader {
  static const int _maxChplScanBytes = 8 * 1024 * 1024;
  static const int _maxMoovBytes = 64 * 1024 * 1024;
  static const int _maxChapterSampleBytes = 64 * 1024;

  /// Retorna a lista de capitulos do arquivo, ou lista vazia se nao tiver.
  static Future<List<M4bChapter>> readChapters(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return [];

    final ext = filePath.toLowerCase().split('.').last;
    if (!['m4b', 'm4a', 'mp4'].contains(ext)) return [];

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final fileSize = await file.length();
      final moov = await _readTopLevelMoov(raf, fileSize);
      if (moov != null) {
        final chpl = _parseChpl(moov);
        if (chpl.isNotEmpty) return chpl;

        final quickTimeChapters = await _parseQuickTimeChap(raf, moov);
        if (quickTimeChapters.isNotEmpty) return quickTimeChapters;
      }

      final readSize = fileSize.clamp(0, _maxChplScanBytes).toInt();
      final bytes = await _readAt(raf, 0, readSize);
      return _parseChpl(bytes);
    } catch (_) {
      return [];
    } finally {
      await raf?.close();
    }
  }

  static Future<Uint8List?> _readTopLevelMoov(
    RandomAccessFile raf,
    int fileSize,
  ) async {
    var offset = 0;
    while (offset + 8 <= fileSize) {
      final box = await _readBoxHeaderFromFile(raf, offset, fileSize);
      if (box == null || box.size <= 0) return null;

      if (box.type == 'moov') {
        final payloadSize = box.size - box.headerSize;
        if (payloadSize <= 0 || payloadSize > _maxMoovBytes) return null;
        return _readAt(raf, box.dataOffset, payloadSize);
      }

      offset += box.size;
    }
    return null;
  }

  static Future<_Mp4Box?> _readBoxHeaderFromFile(
    RandomAccessFile raf,
    int offset,
    int limit,
  ) async {
    final header = await _readAt(raf, offset, 16);
    if (header.length < 8) return null;

    final size32 = _readUint32(header, 0);
    final type = _readAscii(header, 4, 4);
    var size = size32;
    var headerSize = 8;

    if (size32 == 1) {
      if (header.length < 16) return null;
      size = _readUint64(header, 8);
      headerSize = 16;
    } else if (size32 == 0) {
      size = limit - offset;
    }

    if (size < headerSize || offset + size > limit) return null;
    return _Mp4Box(
      type: type,
      offset: offset,
      size: size,
      headerSize: headerSize,
    );
  }

  static Future<Uint8List> _readAt(
    RandomAccessFile raf,
    int offset,
    int length,
  ) async {
    if (length <= 0) return Uint8List(0);
    await raf.setPosition(offset);
    return raf.read(length);
  }

  /// Parseia o atomo `chpl` (iTunes chapter list) dentro do payload de bytes.
  static List<M4bChapter> _parseChpl(Uint8List bytes) {
    final target = [0x63, 0x68, 0x70, 0x6C]; // chpl
    var pos = 0;

    while (pos < bytes.length - 4) {
      if (bytes[pos] == target[0] &&
          bytes[pos + 1] == target[1] &&
          bytes[pos + 2] == target[2] &&
          bytes[pos + 3] == target[3]) {
        try {
          return _decodeChpl(bytes, pos + 4);
        } catch (_) {
          return [];
        }
      }
      pos++;
    }
    return [];
  }

  /// Decodifica dados do atomo `chpl` a partir de [offset] (apos o nome).
  static List<M4bChapter> _decodeChpl(Uint8List bytes, int offset) {
    if (offset + 9 >= bytes.length) return [];

    offset += 5; // version(1) + flags(3) + reserved(1)
    if (offset + 4 >= bytes.length) return [];

    final count = _readUint32(bytes, offset);
    offset += 4;

    if (count <= 0 || count > 5000) return [];

    final chapters = <M4bChapter>[];
    for (var i = 0; i < count; i++) {
      if (offset + 9 > bytes.length) break;

      final rawTs = _readUint64(bytes, offset);
      offset += 8;

      final titleLen = bytes[offset];
      offset += 1;
      if (offset + titleLen > bytes.length) break;

      final titleBytes = bytes.sublist(offset, offset + titleLen);
      offset += titleLen;

      final title = _cleanTitle(utf8.decode(titleBytes, allowMalformed: true));
      final start = Duration(microseconds: rawTs ~/ 10);

      chapters.add(
        M4bChapter(
          index: i,
          title: title.isNotEmpty ? title : 'Capitulo ${i + 1}',
          start: start,
        ),
      );
    }

    return _withEndTimes(chapters);
  }

  static Future<List<M4bChapter>> _parseQuickTimeChap(
    RandomAccessFile raf,
    Uint8List moov,
  ) async {
    final tracks = <_TrackInfo>[];
    for (final box in _boxes(moov, 0, moov.length)) {
      if (box.type == 'trak') {
        final track = _parseTrack(moov, box);
        if (track.id != null) tracks.add(track);
      }
    }

    if (tracks.isEmpty) return [];

    final referencedChapterTrackIds = tracks
        .expand((track) => track.chapterTrackIds)
        .toSet();
    var candidates = tracks
        .where((track) => referencedChapterTrackIds.contains(track.id))
        .toList();

    if (candidates.isEmpty) {
      candidates = tracks.where((track) {
        final handler = track.handlerType;
        return track.sampleTable != null &&
            (handler == 'text' || handler == 'sbtl' || handler == 'subt');
      }).toList();
    }

    for (final track in candidates) {
      final chapters = await _chaptersFromTextTrack(raf, track);
      if (chapters.isNotEmpty) return chapters;
    }

    return [];
  }

  static _TrackInfo _parseTrack(Uint8List bytes, _Mp4Box trak) {
    final track = _TrackInfo();
    final tkhd = _findChild(bytes, trak, 'tkhd');
    if (tkhd != null) track.id = _parseTkhdTrackId(bytes, tkhd);

    final tref = _findChild(bytes, trak, 'tref');
    if (tref != null) {
      final chap = _findChild(bytes, tref, 'chap');
      if (chap != null) {
        for (
          var offset = chap.dataOffset;
          offset + 4 <= chap.end;
          offset += 4
        ) {
          final id = _readUint32(bytes, offset);
          if (id > 0) track.chapterTrackIds.add(id);
        }
      }
    }

    final mdia = _findChild(bytes, trak, 'mdia');
    if (mdia == null) return track;

    final mdhd = _findChild(bytes, mdia, 'mdhd');
    if (mdhd != null) track.timescale = _parseMdhdTimescale(bytes, mdhd);

    final hdlr = _findChild(bytes, mdia, 'hdlr');
    if (hdlr != null && hdlr.dataOffset + 12 <= hdlr.end) {
      track.handlerType = _readAscii(bytes, hdlr.dataOffset + 8, 4);
    }

    final minf = _findChild(bytes, mdia, 'minf');
    final stbl = minf == null ? null : _findChild(bytes, minf, 'stbl');
    if (stbl != null) track.sampleTable = _parseSampleTable(bytes, stbl);

    return track;
  }

  static int? _parseTkhdTrackId(Uint8List bytes, _Mp4Box tkhd) {
    if (tkhd.dataOffset + 4 > tkhd.end) return null;
    final version = bytes[tkhd.dataOffset];
    final idOffset = tkhd.dataOffset + (version == 1 ? 20 : 12);
    if (idOffset + 4 > tkhd.end) return null;
    return _readUint32(bytes, idOffset);
  }

  static int? _parseMdhdTimescale(Uint8List bytes, _Mp4Box mdhd) {
    if (mdhd.dataOffset + 4 > mdhd.end) return null;
    final version = bytes[mdhd.dataOffset];
    final timescaleOffset = mdhd.dataOffset + (version == 1 ? 20 : 12);
    if (timescaleOffset + 4 > mdhd.end) return null;
    final timescale = _readUint32(bytes, timescaleOffset);
    return timescale > 0 ? timescale : null;
  }

  static _SampleTable? _parseSampleTable(Uint8List bytes, _Mp4Box stbl) {
    final stts = _findChild(bytes, stbl, 'stts');
    final stsz = _findChild(bytes, stbl, 'stsz');
    final stsc = _findChild(bytes, stbl, 'stsc');
    final stco = _findChild(bytes, stbl, 'stco');
    final co64 = _findChild(bytes, stbl, 'co64');

    final sampleSizes = stsz == null ? <int>[] : _parseStsz(bytes, stsz);
    final timeToSamples = stts == null
        ? <_SttsEntry>[]
        : _parseStts(bytes, stts);
    final sampleToChunks = stsc == null
        ? <_StscEntry>[]
        : _parseStsc(bytes, stsc);
    final chunkOffsets = co64 != null
        ? _parseChunkOffsets(bytes, co64, is64Bit: true)
        : stco == null
        ? <int>[]
        : _parseChunkOffsets(bytes, stco, is64Bit: false);

    if (sampleSizes.isEmpty || sampleToChunks.isEmpty || chunkOffsets.isEmpty) {
      return null;
    }

    return _SampleTable(
      sampleSizes: sampleSizes,
      timeToSamples: timeToSamples,
      sampleToChunks: sampleToChunks,
      chunkOffsets: chunkOffsets,
    );
  }

  static List<_SttsEntry> _parseStts(Uint8List bytes, _Mp4Box stts) {
    var offset = stts.dataOffset + 4;
    if (offset + 4 > stts.end) return [];
    final count = _readUint32(bytes, offset);
    offset += 4;

    final entries = <_SttsEntry>[];
    for (var i = 0; i < count && offset + 8 <= stts.end; i++) {
      entries.add(
        _SttsEntry(
          sampleCount: _readUint32(bytes, offset),
          sampleDelta: _readUint32(bytes, offset + 4),
        ),
      );
      offset += 8;
    }
    return entries;
  }

  static List<int> _parseStsz(Uint8List bytes, _Mp4Box stsz) {
    var offset = stsz.dataOffset + 4;
    if (offset + 8 > stsz.end) return [];

    final sampleSize = _readUint32(bytes, offset);
    offset += 4;
    final sampleCount = _readUint32(bytes, offset);
    offset += 4;

    if (sampleCount <= 0 || sampleCount > 5000) return [];
    if (sampleSize > 0) return List<int>.filled(sampleCount, sampleSize);

    final sizes = <int>[];
    for (var i = 0; i < sampleCount && offset + 4 <= stsz.end; i++) {
      sizes.add(_readUint32(bytes, offset));
      offset += 4;
    }
    return sizes;
  }

  static List<_StscEntry> _parseStsc(Uint8List bytes, _Mp4Box stsc) {
    var offset = stsc.dataOffset + 4;
    if (offset + 4 > stsc.end) return [];
    final count = _readUint32(bytes, offset);
    offset += 4;

    final entries = <_StscEntry>[];
    for (var i = 0; i < count && offset + 12 <= stsc.end; i++) {
      entries.add(
        _StscEntry(
          firstChunk: _readUint32(bytes, offset),
          samplesPerChunk: _readUint32(bytes, offset + 4),
        ),
      );
      offset += 12;
    }
    return entries
        .where((entry) => entry.firstChunk > 0 && entry.samplesPerChunk > 0)
        .toList()
      ..sort((a, b) => a.firstChunk.compareTo(b.firstChunk));
  }

  static List<int> _parseChunkOffsets(
    Uint8List bytes,
    _Mp4Box box, {
    required bool is64Bit,
  }) {
    var offset = box.dataOffset + 4;
    if (offset + 4 > box.end) return [];
    final count = _readUint32(bytes, offset);
    offset += 4;

    final entrySize = is64Bit ? 8 : 4;
    final offsets = <int>[];
    for (var i = 0; i < count && offset + entrySize <= box.end; i++) {
      offsets.add(
        is64Bit ? _readUint64(bytes, offset) : _readUint32(bytes, offset),
      );
      offset += entrySize;
    }
    return offsets;
  }

  static Future<List<M4bChapter>> _chaptersFromTextTrack(
    RandomAccessFile raf,
    _TrackInfo track,
  ) async {
    final table = track.sampleTable;
    final timescale = track.timescale;
    if (table == null || timescale == null || timescale <= 0) return [];

    final starts = _sampleStartTicks(table);
    final locations = _sampleLocations(table);
    final sampleCount = [
      starts.length,
      locations.length,
    ].reduce((a, b) => a < b ? a : b);
    if (sampleCount == 0) return [];

    final chapters = <M4bChapter>[];
    for (var i = 0; i < sampleCount; i++) {
      final location = locations[i];
      if (location.size <= 0 || location.size > _maxChapterSampleBytes) {
        continue;
      }

      final sample = await _readAt(raf, location.offset, location.size);
      final title = _decodeChapterSample(sample);
      if (title.isEmpty) continue;

      final micros = (starts[i] * 1000000) ~/ timescale;
      chapters.add(
        M4bChapter(
          index: chapters.length,
          title: title,
          start: Duration(microseconds: micros),
        ),
      );
    }

    chapters.sort((a, b) => a.start.compareTo(b.start));
    return _withEndTimes(chapters);
  }

  static List<int> _sampleStartTicks(_SampleTable table) {
    final starts = <int>[];
    var current = 0;
    for (final entry in table.timeToSamples) {
      for (var i = 0; i < entry.sampleCount; i++) {
        if (starts.length >= table.sampleSizes.length) return starts;
        starts.add(current);
        current += entry.sampleDelta;
      }
    }

    while (starts.length < table.sampleSizes.length) {
      starts.add(current);
    }
    return starts;
  }

  static List<_SampleLocation> _sampleLocations(_SampleTable table) {
    final locations = <_SampleLocation>[];
    var sampleIndex = 0;
    var stscIndex = 0;

    for (
      var chunkIndex = 0;
      chunkIndex < table.chunkOffsets.length;
      chunkIndex++
    ) {
      final chunkNumber = chunkIndex + 1;
      while (stscIndex + 1 < table.sampleToChunks.length &&
          table.sampleToChunks[stscIndex + 1].firstChunk <= chunkNumber) {
        stscIndex++;
      }

      final samplesPerChunk = table.sampleToChunks[stscIndex].samplesPerChunk;
      var offset = table.chunkOffsets[chunkIndex];
      for (var i = 0; i < samplesPerChunk; i++) {
        if (sampleIndex >= table.sampleSizes.length) return locations;
        final size = table.sampleSizes[sampleIndex];
        locations.add(_SampleLocation(offset: offset, size: size));
        offset += size;
        sampleIndex++;
      }
    }

    return locations;
  }

  static String _decodeChapterSample(Uint8List sample) {
    if (sample.isEmpty) return '';

    if (sample.length >= 2) {
      final length = (sample[0] << 8) | sample[1];
      if (length > 0 && length <= sample.length - 2) {
        return _decodeTextPayload(sample.sublist(2, 2 + length));
      }
    }

    if (sample.isNotEmpty) {
      final length = sample[0];
      if (length > 0 && length <= sample.length - 1) {
        final title = _decodeTextPayload(sample.sublist(1, 1 + length));
        if (title.isNotEmpty) return title;
      }
    }

    return _decodeTextPayload(sample);
  }

  static String _decodeTextPayload(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _cleanTitle(_decodeUtf16(bytes.sublist(2), littleEndian: false));
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _cleanTitle(_decodeUtf16(bytes.sublist(2), littleEndian: true));
    }

    final evenNulls = bytes.indexed
        .where((entry) => entry.$1.isEven && entry.$2 == 0)
        .length;
    final oddNulls = bytes.indexed
        .where((entry) => entry.$1.isOdd && entry.$2 == 0)
        .length;
    if (bytes.length >= 4 &&
        (evenNulls > bytes.length ~/ 4 || oddNulls > bytes.length ~/ 4)) {
      return _cleanTitle(
        _decodeUtf16(bytes, littleEndian: oddNulls > evenNulls),
      );
    }

    return _cleanTitle(utf8.decode(bytes, allowMalformed: true));
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final codes = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final code = littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1];
      if (code != 0) codes.add(code);
    }
    return String.fromCharCodes(codes);
  }

  static List<M4bChapter> _withEndTimes(List<M4bChapter> chapters) {
    if (chapters.length < 2) return chapters;

    return [
      for (var i = 0; i < chapters.length; i++)
        M4bChapter(
          index: i,
          title: chapters[i].title,
          start: chapters[i].start,
          end: i + 1 < chapters.length
              ? chapters[i + 1].start
              : chapters[i].end,
        ),
    ];
  }

  static List<_Mp4Box> _boxes(Uint8List bytes, int start, int end) {
    final boxes = <_Mp4Box>[];
    var offset = start;
    while (offset + 8 <= end) {
      final box = _readBoxHeader(bytes, offset, end);
      if (box == null || box.size <= 0) break;
      boxes.add(box);
      offset = box.end;
    }
    return boxes;
  }

  static _Mp4Box? _findChild(Uint8List bytes, _Mp4Box parent, String type) {
    for (final child in _boxes(bytes, parent.dataOffset, parent.end)) {
      if (child.type == type) return child;
    }
    return null;
  }

  static _Mp4Box? _readBoxHeader(Uint8List bytes, int offset, int limit) {
    if (offset + 8 > limit) return null;

    final size32 = _readUint32(bytes, offset);
    final type = _readAscii(bytes, offset + 4, 4);
    var size = size32;
    var headerSize = 8;

    if (size32 == 1) {
      if (offset + 16 > limit) return null;
      size = _readUint64(bytes, offset + 8);
      headerSize = 16;
    } else if (size32 == 0) {
      size = limit - offset;
    }

    if (size < headerSize || offset + size > limit) return null;
    return _Mp4Box(
      type: type,
      offset: offset,
      size: size,
      headerSize: headerSize,
    );
  }

  static int _readUint32(Uint8List bytes, int offset) {
    return ((bytes[offset] << 24) |
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3]) &
        0xFFFFFFFF;
  }

  static int _readUint64(Uint8List bytes, int offset) {
    var result = 0;
    for (var i = 0; i < 8; i++) {
      result = (result << 8) | (bytes[offset + i] & 0xFF);
    }
    return result;
  }

  static String _readAscii(Uint8List bytes, int offset, int length) {
    if (offset + length > bytes.length) return '';
    return String.fromCharCodes(bytes.sublist(offset, offset + length));
  }

  static String _cleanTitle(String value) {
    return value
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[\x00-\x1F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _Mp4Box {
  final String type;
  final int offset;
  final int size;
  final int headerSize;

  const _Mp4Box({
    required this.type,
    required this.offset,
    required this.size,
    required this.headerSize,
  });

  int get dataOffset => offset + headerSize;
  int get end => offset + size;
}

class _TrackInfo {
  int? id;
  int? timescale;
  String? handlerType;
  final List<int> chapterTrackIds = [];
  _SampleTable? sampleTable;
}

class _SampleTable {
  final List<int> sampleSizes;
  final List<_SttsEntry> timeToSamples;
  final List<_StscEntry> sampleToChunks;
  final List<int> chunkOffsets;

  const _SampleTable({
    required this.sampleSizes,
    required this.timeToSamples,
    required this.sampleToChunks,
    required this.chunkOffsets,
  });
}

class _SttsEntry {
  final int sampleCount;
  final int sampleDelta;

  const _SttsEntry({required this.sampleCount, required this.sampleDelta});
}

class _StscEntry {
  final int firstChunk;
  final int samplesPerChunk;

  const _StscEntry({required this.firstChunk, required this.samplesPerChunk});
}

class _SampleLocation {
  final int offset;
  final int size;

  const _SampleLocation({required this.offset, required this.size});
}
