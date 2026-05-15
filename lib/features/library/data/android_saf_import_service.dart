import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/local_folder_import.dart';

class AndroidSafImportService {
  static const _channel = MethodChannel('minha_estante/saf_import');
  static final _progressController =
      StreamController<LocalFolderImportProgress>.broadcast();
  static bool _progressHandlerReady = false;

  static bool get isSupported => Platform.isAndroid;
  static Stream<LocalFolderImportProgress> get progressStream {
    _ensureProgressHandler();
    return _progressController.stream;
  }

  AndroidSafImportService() {
    _ensureProgressHandler();
  }

  static void reportProgress(LocalFolderImportProgress progress) {
    _progressController.add(progress);
  }

  static void _ensureProgressHandler() {
    if (_progressHandlerReady) return;
    _progressHandlerReady = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'importProgress') return;
      final raw = Map<String, dynamic>.from(call.arguments as Map);
      _progressController.add(
        LocalFolderImportProgress(
          current: (raw['current'] as num?)?.toInt() ?? 0,
          total: (raw['total'] as num?)?.toInt() ?? 0,
          fileName: raw['fileName'] as String?,
          phase: raw['phase'] as String? ?? 'importing',
        ),
      );
    });
  }

  Future<LocalFolderImport?> pickFolder() async {
    if (!isSupported) return null;
    final Map<String, dynamic>? result;
    try {
      result = await _channel.invokeMapMethod<String, dynamic>('pickFolder');
    } on MissingPluginException {
      throw Exception(
        'O importador de pastas foi atualizado. Feche o app e rode flutter run novamente para instalar a parte Android.',
      );
    }
    if (result == null) return null;
    return _fromMap(result);
  }

  Future<LocalFolderImport> syncFolder(String uri) async {
    final Map<String, dynamic>? result;
    try {
      result = await _channel.invokeMapMethod<String, dynamic>('syncFolder', {
        'uri': uri,
      });
    } on MissingPluginException {
      throw Exception(
        'O importador de pastas foi atualizado. Feche o app e rode flutter run novamente para instalar a parte Android.',
      );
    }
    if (result == null) {
      throw Exception('Não foi possível acessar a pasta selecionada.');
    }
    return _fromMap(result);
  }

  Future<Uint8List> readFileBytes(String uri) async {
    final result = await _channel.invokeMethod<Uint8List>('readFileBytes', {
      'uri': uri,
    });
    if (result == null) {
      throw Exception('Falha ao ler bytes do arquivo: $uri');
    }
    return result;
  }

  LocalFolderImport _fromMap(Map<String, dynamic> map) {
    final filesRaw = (map['files'] as List<dynamic>? ?? const []);
    final files = filesRaw.map((raw) {
      final fileMap = Map<String, dynamic>.from(raw as Map);
      return LocalFolderImportedFile(
        name: fileMap['name'] as String,
        path: fileMap['path'] as String,
        relativePath: fileMap['relativePath'] as String?,
        modifiedMillis: (fileMap['modifiedMillis'] as num?)?.toInt(),
      );
    }).toList();

    return LocalFolderImport(
      name: map['name'] as String,
      path: map['uri'] as String,
      files: files,
    );
  }
}
