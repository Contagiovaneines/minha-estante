import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minha_estante/features/reader/domain/cbr_to_cbz_converter_service.dart';
import 'package:minha_estante/features/reader/domain/cbz_reader_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nativeChannel = MethodChannel('minha_estante/native_archive');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cbr_converter_test_');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          switch (call.method) {
            case 'getTemporaryDirectory':
            case 'getApplicationDocumentsDirectory':
              return tempDir.path;
          }
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          if (call.method == 'convertCbrToCbz') {
            throw PlatformException(
              code: 'CONVERSION_FAILED',
              message:
                  'Não foi possível converter este CBR. Tente converter manualmente para CBZ.',
            );
          }
          if (call.method == 'copyArchiveUriToCache') {
            throw PlatformException(code: 'COPY_FAILED', message: 'not used');
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fallback ZIP streams only safe image entries into CBZ cache', () async {
    final page2 = File(p.join(tempDir.path, 'page2.png'))
      ..writeAsBytesSync([2, 2, 2]);
    final page10 = File(p.join(tempDir.path, 'page10.jpg'))
      ..writeAsBytesSync([10, 10, 10]);
    final renamedCbz = File(p.join(tempDir.path, 'renamed.cbr'));

    final encoder = ZipFileEncoder()..create(renamedCbz.path);
    await encoder.addFile(page10, 'pages/page10.jpg');
    await encoder.addFile(page2, 'pages/page2.png');
    encoder.addArchiveFile(ArchiveFile.bytes('../evil.jpg', [1]));
    encoder.addArchiveFile(ArchiveFile.bytes('__MACOSX/page1.jpg', [1]));
    encoder.addArchiveFile(ArchiveFile.bytes('.DS_Store', [1]));
    encoder.addArchiveFile(ArchiveFile.bytes('notes.txt', [1]));
    await encoder.close();

    final converted = await CbrToCbzConverterService().convertCbrToCbz(
      renamedCbz,
    );

    expect(converted.path, contains('cbr_cache'));
    expect(await converted.exists(), isTrue);

    final input = InputFileStream(converted.path);
    final archive = ZipDecoder().decodeStream(input);
    input.closeSync();

    final names = archive.files.where((file) => file.isFile).map((file) {
      return file.name;
    }).toList();

    expect(names, ['0001_page2.png', '0002_page10.jpg']);
    expect(names.any((name) => name.contains('..')), isFalse);
    expect(names.any((name) => name.contains('__MACOSX')), isFalse);
  });

  test('CBZ reader extracts only files with valid image signatures', () async {
    final validPng = File(p.join(tempDir.path, 'page1.png'))
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
        ),
      );
    final invalidJpg = File(p.join(tempDir.path, 'page2.jpg'))
      ..writeAsBytesSync([1, 2, 3, 4]);
    final cbz = File(p.join(tempDir.path, 'sample.cbz'));

    final encoder = ZipFileEncoder()..create(cbz.path);
    await encoder.addFile(validPng, 'page1.png');
    await encoder.addFile(invalidJpg, 'page2.jpg');
    await encoder.close();

    final pages = await CbzReaderService().extractCbz(cbz.path, 'test_item');

    expect(pages, hasLength(1));
    expect(p.basename(pages.single.path), 'page1.png');
    expect(await pages.single.length(), greaterThan(8));
  });
}
