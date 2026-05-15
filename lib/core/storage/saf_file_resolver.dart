import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../features/library/data/android_saf_import_service.dart';

/// Helper para resolver URIs do Android (content://) para arquivos locais acessíveis.
/// Essencial para compatibilidade com Android 11 a 16+.
class SafFileResolver {
  static final _safService = AndroidSafImportService();

  /// Resolve um caminho ou URI para um [File] que o app consiga ler.
  /// Se for content://, copia para o cache interno.
  static Future<File> resolveForProcessing(String pathOrUri) async {
    final file = File(pathOrUri);

    // Se o caminho já for acessível diretamente (ex: cache interno), usa ele.
    if (pathOrUri.startsWith('/') && await file.exists()) {
      return file;
    }

    // Se for content:// ou um caminho inacessível no Android 11-16
    if (pathOrUri.startsWith('content://') || Platform.isAndroid) {
      return await copyUriToCache(pathOrUri);
    }

    return file;
  }

  /// Copia um arquivo via URI para a pasta de cache do app.
  static Future<File> copyUriToCache(String uri) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final fileName = _getFileNameFromUri(uri);
      final targetFile = File(p.join(cacheDir.path, 'saf_cache', fileName));

      // Cria subpasta se não existir
      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }

      // Lê os bytes via MethodChannel (SAF)
      final bytes = await _safService.readFileBytes(uri);
      await targetFile.writeAsBytes(bytes);

      return targetFile;
    } catch (e) {
      throw Exception('Falha ao acessar arquivo via SAF: $e');
    }
  }

  static String _getFileNameFromUri(String uri) {
    // Tenta extrair o nome do arquivo da URI ou usa um hash
    final decoded = Uri.decodeFull(uri);
    final lastPart = decoded.split('/').last;
    if (lastPart.contains('.')) return lastPart;
    
    // Fallback: usa hash da URI para evitar conflitos
    return 'file_${uri.hashCode}.tmp';
  }
}
