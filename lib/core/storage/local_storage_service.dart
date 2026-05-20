import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

class LocalStorageService {
  static const String _usersBox = 'users';
  static const String _currentUserKey = 'current_user';
  static const String _sourcesBox = 'sources';
  static const String _localFoldersPrefix = 'local_folders_';
  static const String _itemsBox = 'items';
  static const String _progressBox = 'progress';
  static const String _settingsBox = 'settings';
  static const String _bookmarksBox = 'bookmarks';
  static const String _sessionsBox = 'sessions';

  static late Box<String> _users;
  static late Box<String> _sources;
  static late Box<String> _items;
  static late Box<String> _progress;
  static late Box<String> _settings;
  static late Box<String> _bookmarks;
  static late Box<String> _sessions;

  static Future<void> init() async {
    _users = await Hive.openBox<String>(_usersBox);
    _sources = await Hive.openBox<String>(_sourcesBox);
    _items = await Hive.openBox<String>(_itemsBox);
    _progress = await Hive.openBox<String>(_progressBox);
    _settings = await Hive.openBox<String>(_settingsBox);
    _bookmarks = await Hive.openBox<String>(_bookmarksBox);
    _sessions = await Hive.openBox<String>(_sessionsBox);
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    final id = user['id'] as String;
    await _users.put('user_$id', jsonEncode(user));
  }

  static Map<String, dynamic>? getUserByEmail(String email) {
    for (final value in _users.values) {
      final map = jsonDecode(value) as Map<String, dynamic>;
      if (map['email'] == email) return map;
    }
    return null;
  }

  static Map<String, dynamic>? getUserById(String id) {
    final raw = _users.get('user_$id');
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> setCurrentUserId(String? id) async {
    if (id == null) {
      await _settings.delete(_currentUserKey);
    } else {
      await _settings.put(_currentUserKey, id);
    }
  }

  static String? getCurrentUserId() {
    return _settings.get(_currentUserKey);
  }

  static Future<void> saveSources(
    String userId,
    List<Map<String, dynamic>> sources,
  ) async {
    await _sources.put(userId, jsonEncode(sources));
  }

  static List<Map<String, dynamic>> getSources(String userId) {
    final raw = _sources.get(userId);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> saveLocalFolders(
    String userId,
    List<Map<String, dynamic>> folders,
  ) async {
    await _sources.put('$_localFoldersPrefix$userId', jsonEncode(folders));
  }

  static List<Map<String, dynamic>> getLocalFolders(String userId) {
    final raw = _sources.get('$_localFoldersPrefix$userId');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> saveItems(
    String userId,
    List<Map<String, dynamic>> items,
  ) async {
    await _items.put(userId, jsonEncode(items));
  }

  static List<Map<String, dynamic>> getItems(String userId) {
    final raw = _items.get(userId);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> saveProgress(
    String userId,
    Map<String, dynamic> progress,
  ) async {
    await _progress.put(
      '${userId}_${progress['itemId']}',
      jsonEncode(progress),
    );
  }

  static Map<String, dynamic>? getProgress(String userId, String itemId) {
    final raw = _progress.get('${userId}_$itemId');
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static List<Map<String, dynamic>> getAllProgress(String userId) {
    final result = <Map<String, dynamic>>[];
    for (final key in _progress.keys) {
      if (key.toString().startsWith('${userId}_')) {
        final raw = _progress.get(key);
        if (raw != null) {
          result.add(jsonDecode(raw) as Map<String, dynamic>);
        }
      }
    }
    return result;
  }

  static String? getSetting(String key) => _settings.get(key);
  static Future<void> setSetting(String key, String value) =>
      _settings.put(key, value);

  static String _ttsProgressKey(String userId, String itemId) =>
      'tts_progress_${userId}_$itemId';

  static Future<void> saveTtsProgress(
    String userId,
    Map<String, dynamic> progress,
  ) async {
    await _settings.put(
      _ttsProgressKey(userId, progress['itemId'] as String),
      jsonEncode(progress),
    );
  }

  static Map<String, dynamic>? getTtsProgress(String userId, String itemId) {
    final raw = _settings.get(_ttsProgressKey(userId, itemId));
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static String _lastOpenedItemKey(String userId) => 'last_opened_item_$userId';

  static Future<void> saveLastOpenedItemId(String userId, String itemId) async {
    await _settings.put(_lastOpenedItemKey(userId), itemId);
  }

  static String? getLastOpenedItemId(String userId) {
    return _settings.get(_lastOpenedItemKey(userId));
  }

  static Future<void> clearLastOpenedItemId(String userId) async {
    await _settings.delete(_lastOpenedItemKey(userId));
  }

  static Future<void> clearItemState(String userId, String itemId) async {
    await _progress.delete('${userId}_$itemId');
    await _bookmarks.delete(_bookmarkKey(userId, itemId));
    await _settings.delete(_ttsProgressKey(userId, itemId));
    await clearReadingSessionsForItems(userId, {itemId});
    if (getLastOpenedItemId(userId) == itemId) {
      await clearLastOpenedItemId(userId);
    }
  }

  static String? getProfileImage(String userId) {
    return _settings.get('profile_image_$userId');
  }

  static Future<void> setProfileImage(String userId, String path) async {
    await _settings.put('profile_image_$userId', path);
  }

  // ─── Bookmarks ─────────────────────────────────────────────────────────────

  static String _bookmarkKey(String userId, String itemId) =>
      '${userId}_$itemId';

  static Future<void> saveBookmark(
    String userId,
    Map<String, dynamic> bookmark,
  ) async {
    final itemId = bookmark['itemId'] as String;
    final existing = getBookmarks(userId, itemId);
    existing.removeWhere((b) => b['id'] == bookmark['id']);
    existing.add(bookmark);
    await _bookmarks.put(_bookmarkKey(userId, itemId), jsonEncode(existing));
  }

  static List<Map<String, dynamic>> getBookmarks(String userId, String itemId) {
    final raw = _bookmarks.get(_bookmarkKey(userId, itemId));
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<void> deleteBookmark(
    String userId,
    String itemId,
    String bookmarkId,
  ) async {
    final existing = getBookmarks(userId, itemId);
    existing.removeWhere((b) => b['id'] == bookmarkId);
    await _bookmarks.put(_bookmarkKey(userId, itemId), jsonEncode(existing));
  }

  static List<Map<String, dynamic>> getAllBookmarks(String userId) {
    final result = <Map<String, dynamic>>[];
    for (final key in _bookmarks.keys) {
      if (key.toString().startsWith('${userId}_')) {
        final raw = _bookmarks.get(key);
        if (raw != null) {
          final list = jsonDecode(raw) as List<dynamic>;
          result.addAll(list.cast<Map<String, dynamic>>());
        }
      }
    }
    return result;
  }

  // ─── Reading Sessions ───────────────────────────────────────────────────────

  /// Registra uma sessão de leitura com data e duração em segundos.
  static Future<void> saveReadingSession({
    required String userId,
    required String itemId,
    required int durationSeconds,
  }) async {
    final key = 'sessions_$userId';
    final raw = _sessions.get(key);
    final sessions = raw != null
        ? (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    sessions.add({
      'itemId': itemId,
      'date': DateTime.now().toIso8601String(),
      'durationSeconds': durationSeconds,
    });
    // Keep max 500 sessions to avoid storage bloat
    final trimmed = sessions.length > 500
        ? sessions.sublist(sessions.length - 500)
        : sessions;
    await _sessions.put(key, jsonEncode(trimmed));
  }

  static List<Map<String, dynamic>> getReadingSessions(String userId) {
    final raw = _sessions.get('sessions_$userId');
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
  }

  static Future<void> clearReadingSessionsForItems(
    String userId,
    Set<String> itemIds,
  ) async {
    if (itemIds.isEmpty) return;

    final key = 'sessions_$userId';
    final raw = _sessions.get(key);
    if (raw == null) return;

    final sessions = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final filtered = sessions
        .where((session) => !itemIds.contains(session['itemId']))
        .toList();

    if (filtered.isEmpty) {
      await _sessions.delete(key);
    } else if (filtered.length != sessions.length) {
      await _sessions.put(key, jsonEncode(filtered));
    }
  }

  // ─── Upsert (used by backup restore) ───────────────────────────────────────

  /// Sobrescreve ou adiciona um item pelo id dentro da lista do userId.
  static Future<void> upsertItem(
    String userId,
    Map<String, dynamic> item,
  ) async {
    final existing = getItems(userId);
    final idx = existing.indexWhere((e) => e['id'] == item['id']);
    if (idx >= 0) {
      existing[idx] = item;
    } else {
      existing.add(item);
    }
    await saveItems(userId, existing);
  }

  static Future<void> clearCache(String userId) async {
    await _items.delete(userId);
    final progressKeys = _progress.keys
        .where((k) => k.toString().startsWith('${userId}_'))
        .toList();
    for (final key in progressKeys) {
      await _progress.delete(key);
    }
    final ttsProgressKeys = _settings.keys
        .where((k) => k.toString().startsWith('tts_progress_${userId}_'))
        .toList();
    for (final key in ttsProgressKeys) {
      await _settings.delete(key);
    }
    final bookmarkKeys = _bookmarks.keys
        .where((k) => k.toString().startsWith('${userId}_'))
        .toList();
    for (final key in bookmarkKeys) {
      await _bookmarks.delete(key);
    }
    await _sessions.delete('sessions_$userId');
    await _sources.delete('$_localFoldersPrefix$userId');
    await clearLastOpenedItemId(userId);
  }
}
