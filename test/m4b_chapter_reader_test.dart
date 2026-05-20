import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:minha_estante/features/audio/domain/m4b_chapter_reader.dart';
import 'package:path/path.dart' as p;

void main() {
  test('reads QuickTime chap text track chapters', () async {
    final tempDir = await Directory.systemTemp.createTemp('m4b_chap_test_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final file = File(p.join(tempDir.path, 'chapters.m4b'));
    await file.writeAsBytes(_quickTimeChapMp4Bytes());

    final chapters = await M4bChapterReader.readChapters(file.path);

    expect(chapters, hasLength(2));
    expect(chapters[0].title, 'Intro');
    expect(chapters[0].start, Duration.zero);
    expect(chapters[0].end, const Duration(seconds: 5));
    expect(chapters[1].title, 'Chapter 2');
    expect(chapters[1].start, const Duration(seconds: 5));
  });
}

Uint8List _quickTimeChapMp4Bytes() {
  final samples = [_textSample('Intro'), _textSample('Chapter 2')];
  final ftyp = _box('ftyp', [
    ...ascii.encode('M4A '),
    ..._u32(0),
    ...ascii.encode('M4A '),
    ...ascii.encode('mp42'),
  ]);

  Uint8List buildMoov(List<int> chunkOffsets) {
    return _box('moov', [
      ..._box('trak', [
        ..._tkhd(1),
        ..._box('tref', [..._box('chap', _u32(2))]),
      ]),
      ..._box('trak', [
        ..._tkhd(2),
        ..._box('mdia', [
          ..._mdhd(timescale: 1000),
          ..._hdlr('text'),
          ..._box('minf', [
            ..._box('stbl', [
              ..._stts([(count: 1, delta: 5000), (count: 1, delta: 7000)]),
              ..._stsc(firstChunk: 1, samplesPerChunk: 1),
              ..._stsz(samples.map((sample) => sample.length).toList()),
              ..._stco(chunkOffsets),
            ]),
          ]),
        ]),
      ]),
    ]);
  }

  var moov = buildMoov([0, 0]);
  final firstSampleOffset = ftyp.length + moov.length + 8;
  final chunkOffsets = [
    firstSampleOffset,
    firstSampleOffset + samples.first.length,
  ];
  moov = buildMoov(chunkOffsets);

  final mdat = _box('mdat', samples.expand((sample) => sample).toList());
  return Uint8List.fromList([...ftyp, ...moov, ...mdat]);
}

Uint8List _textSample(String title) {
  final titleBytes = utf8.encode(title);
  return Uint8List.fromList([
    (titleBytes.length >> 8) & 0xff,
    titleBytes.length & 0xff,
    ...titleBytes,
  ]);
}

Uint8List _box(String type, List<int> payload) {
  return Uint8List.fromList([
    ..._u32(payload.length + 8),
    ...ascii.encode(type),
    ...payload,
  ]);
}

Uint8List _tkhd(int trackId) {
  return _box('tkhd', [
    0,
    0,
    0,
    3,
    ..._u32(0),
    ..._u32(0),
    ..._u32(trackId),
    ..._u32(0),
    ..._u32(0),
  ]);
}

Uint8List _mdhd({required int timescale}) {
  return _box('mdhd', [
    0,
    0,
    0,
    0,
    ..._u32(0),
    ..._u32(0),
    ..._u32(timescale),
    ..._u32(12000),
    0,
    0,
    0,
    0,
  ]);
}

Uint8List _hdlr(String handler) {
  return _box('hdlr', [
    0,
    0,
    0,
    0,
    ..._u32(0),
    ...ascii.encode(handler),
    ..._u32(0),
    ..._u32(0),
    ..._u32(0),
  ]);
}

Uint8List _stts(List<({int count, int delta})> entries) {
  return _box('stts', [
    0,
    0,
    0,
    0,
    ..._u32(entries.length),
    for (final entry in entries) ...[
      ..._u32(entry.count),
      ..._u32(entry.delta),
    ],
  ]);
}

Uint8List _stsc({required int firstChunk, required int samplesPerChunk}) {
  return _box('stsc', [
    0,
    0,
    0,
    0,
    ..._u32(1),
    ..._u32(firstChunk),
    ..._u32(samplesPerChunk),
    ..._u32(1),
  ]);
}

Uint8List _stsz(List<int> sampleSizes) {
  return _box('stsz', [
    0,
    0,
    0,
    0,
    ..._u32(0),
    ..._u32(sampleSizes.length),
    for (final size in sampleSizes) ..._u32(size),
  ]);
}

Uint8List _stco(List<int> chunkOffsets) {
  return _box('stco', [
    0,
    0,
    0,
    0,
    ..._u32(chunkOffsets.length),
    for (final offset in chunkOffsets) ..._u32(offset),
  ]);
}

Uint8List _u32(int value) {
  return Uint8List.fromList([
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ]);
}
