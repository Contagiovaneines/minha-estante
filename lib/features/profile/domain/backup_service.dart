import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/storage/local_storage_service.dart';

/// Exporta e importa a biblioteca completa como JSON local.
class BackupService {
  // ─── Export ─────────────────────────────────────────────────────────────────

  /// Gera o backup e retorna o caminho do arquivo criado.
  Future<String> exportBackup(String userId) async {
    final items = LocalStorageService.getItems(userId);
    final progress = LocalStorageService.getAllProgress(userId);
    final ttsProgress = _getTtsProgress(userId);
    final userData = LocalStorageService.getUserById(userId);
    final localFolders = LocalStorageService.getLocalFolders(userId);
    final bookmarks = LocalStorageService.getAllBookmarks(userId);
    final sessions = LocalStorageService.getReadingSessions(userId);

    final backup = {
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'user': userData,
      'items': items,
      'progress': progress,
      'ttsProgress': ttsProgress,
      'localFolders': localFolders,
      'bookmarks': bookmarks,
      'sessions': sessions,
    };

    final json = const JsonEncoder.withIndent('  ').convert(backup);
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final file = File('${dir.path}/minha_estante_backup_$timestamp.json');
    await file.writeAsString(json, encoding: utf8);
    return file.path;
  }

  List<Map<String, dynamic>> _getTtsProgress(String userId) {
    final result = <Map<String, dynamic>>[];
    final items = LocalStorageService.getItems(userId);
    for (final item in items) {
      final id = item['id'] as String?;
      if (id == null) continue;
      final raw = LocalStorageService.getTtsProgress(userId, id);
      if (raw != null) result.add(raw);
    }
    return result;
  }

  // ─── Import ─────────────────────────────────────────────────────────────────

  /// Importa um backup JSON e retorna um mapa com contagens.
  Future<BackupImportResult> importBackup(
    String filePath,
    String userId,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Arquivo não encontrado: $filePath');
    }

    final raw = await file.readAsString(encoding: utf8);
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      throw Exception(
        'Arquivo JSON inválido. Verifique se é um backup do Minha Estante.',
      );
    }

    final version = data['version'] as int? ?? 1;
    if (version < 1 || version > 2) {
      throw Exception('Versão de backup não suportada: $version');
    }

    int itemsRestored = 0;
    int progressRestored = 0;
    int bookmarksRestored = 0;

    // ─── Items
    final rawItems = data['items'] as List<dynamic>? ?? [];
    for (final raw in rawItems) {
      final item = raw as Map<String, dynamic>;
      // Rewrite userId to match current local user
      item['userId'] = userId;
      await LocalStorageService.upsertItem(userId, item);
      itemsRestored++;
    }

    // ─── Progress
    final rawProgress = data['progress'] as List<dynamic>? ?? [];
    for (final raw in rawProgress) {
      final prog = Map<String, dynamic>.from(raw as Map<String, dynamic>);
      prog['userId'] = userId;
      await LocalStorageService.saveProgress(userId, prog);
      progressRestored++;
    }

    // ─── TTS Progress (version 1+)
    final rawTts = data['ttsProgress'] as List<dynamic>? ?? [];
    for (final raw in rawTts) {
      final tts = Map<String, dynamic>.from(raw as Map<String, dynamic>);
      final itemId = tts['itemId'] as String?;
      if (itemId != null) {
        tts['userId'] = userId;
        await LocalStorageService.saveTtsProgress(userId, tts);
      }
    }

    // ─── Bookmarks (version 2+)
    if (version >= 2) {
      final rawBookmarks = data['bookmarks'] as List<dynamic>? ?? [];
      for (final raw in rawBookmarks) {
        final bm = Map<String, dynamic>.from(raw as Map<String, dynamic>);
        bm['userId'] = userId;
        await LocalStorageService.saveBookmark(userId, bm);
        bookmarksRestored++;
      }
    }

    return BackupImportResult(
      itemsRestored: itemsRestored,
      progressRestored: progressRestored,
      bookmarksRestored: bookmarksRestored,
    );
  }
}

class BackupImportResult {
  final int itemsRestored;
  final int progressRestored;
  final int bookmarksRestored;

  const BackupImportResult({
    required this.itemsRestored,
    required this.progressRestored,
    required this.bookmarksRestored,
  });

  String get summary {
    final parts = <String>[];
    if (itemsRestored > 0) parts.add('$itemsRestored itens');
    if (progressRestored > 0) parts.add('$progressRestored progressos');
    if (bookmarksRestored > 0) parts.add('$bookmarksRestored marcadores');
    return parts.isEmpty
        ? 'Nada restaurado.'
        : '${parts.join(', ')} restaurados!';
  }
}
