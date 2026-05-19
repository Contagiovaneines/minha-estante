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

  static late Box<String> _users;
  static late Box<String> _sources;
  static late Box<String> _items;
  static late Box<String> _progress;
  static late Box<String> _settings;

  static Future<void> init() async {
    _users = await Hive.openBox<String>(_usersBox);
    _sources = await Hive.openBox<String>(_sourcesBox);
    _items = await Hive.openBox<String>(_itemsBox);
    _progress = await Hive.openBox<String>(_progressBox);
    _settings = await Hive.openBox<String>(_settingsBox);
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

  static bool hasDriveSetup(String userId) {
    return _settings.containsKey('drive_setup_$userId');
  }

  static bool isDriveEnabled(String userId) {
    return _settings.get('drive_enabled_$userId') == 'true';
  }

  static String? getDriveApiKey(String userId) {
    return _settings.get('drive_api_key_$userId');
  }

  static String? getProfileImage(String userId) {
    return _settings.get('profile_image_$userId');
  }

  static Future<void> setProfileImage(String userId, String path) async {
    await _settings.put('profile_image_$userId', path);
  }

  static Future<void> saveDriveSettings(
    String userId, {
    required bool enabled,
    String? apiKey,
  }) async {
    await _settings.put('drive_setup_$userId', 'true');
    await _settings.put('drive_enabled_$userId', enabled ? 'true' : 'false');
    if (apiKey != null && apiKey.isNotEmpty) {
      await _settings.put('drive_api_key_$userId', apiKey);
    } else {
      await _settings.delete('drive_api_key_$userId');
    }
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
    await clearLastOpenedItemId(userId);
  }
}
