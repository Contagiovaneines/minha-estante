import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class NativeOpenedArchive {
  final String uri;
  final String? name;
  final String? mimeType;

  const NativeOpenedArchive({required this.uri, this.name, this.mimeType});

  factory NativeOpenedArchive.fromMap(Map<dynamic, dynamic> map) {
    return NativeOpenedArchive(
      uri: map['uri'] as String,
      name: map['name'] as String?,
      mimeType: map['mimeType'] as String?,
    );
  }
}

class NativeArchiveService {
  static const MethodChannel _channel = MethodChannel(
    'minha_estante/native_archive',
  );
  static final _openedArchiveController =
      StreamController<NativeOpenedArchive>.broadcast();
  static bool _openHandlerReady = false;

  static Stream<NativeOpenedArchive> get openedArchiveStream {
    _ensureOpenHandler();
    return _openedArchiveController.stream;
  }

  NativeArchiveService() {
    _ensureOpenHandler();
  }

  static void _ensureOpenHandler() {
    if (_openHandlerReady) return;
    _openHandlerReady = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openArchive') return;
      final raw = call.arguments;
      if (raw is Map) {
        _openedArchiveController.add(NativeOpenedArchive.fromMap(raw));
      }
    });
  }

  Future<NativeOpenedArchive?> consumeInitialOpenedArchive() async {
    _ensureOpenHandler();
    try {
      final result = await _channel.invokeMapMethod<dynamic, dynamic>(
        'consumeInitialOpenedArchive',
      );
      if (result == null) return null;
      return NativeOpenedArchive.fromMap(result);
    } on MissingPluginException {
      return null;
    }
  }

  /// Converte um arquivo CBR para CBZ usando o Android nativo.
  /// Recebe um path local ou uma URI (content://).
  /// Retorna o path do CBZ convertido.
  Future<File> convertCbrToCbz(String uriOrPath) async {
    try {
      final String? cbzPath = await _channel.invokeMethod('convertCbrToCbz', {
        'uri': uriOrPath,
      });

      if (cbzPath == null || cbzPath.isEmpty) {
        throw Exception('Caminho de retorno inválido.');
      }

      final file = File(cbzPath);
      if (!await file.exists()) {
        throw Exception('Arquivo convertido não encontrado no cache.');
      }

      return file;
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Erro desconhecido ao converter CBR nativamente.',
      );
    } catch (e) {
      throw Exception('Erro na ponte nativa: $e');
    }
  }

  /// Copia uma URI content:// para o cache interno usando stream nativo.
  Future<File> copyArchiveUriToCache(String uri) async {
    try {
      final String? path = await _channel.invokeMethod(
        'copyArchiveUriToCache',
        {'uri': uri},
      );
      if (path == null || path.isEmpty) {
        throw Exception('Caminho de cache inválido.');
      }
      final file = File(path);
      if (!await file.exists()) {
        throw Exception('Arquivo copiado não encontrado no cache.');
      }
      return file;
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Erro desconhecido ao copiar CBR.');
    } catch (e) {
      throw Exception('Erro na ponte nativa: $e');
    }
  }
}
