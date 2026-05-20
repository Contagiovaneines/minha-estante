import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/local_storage_service.dart';
import '../domain/app_user.dart';
import 'auth_repository.dart';

class LocalAuthRepository implements AuthRepository {
  final _uuid = const Uuid();

  static const _localUserId = 'local_profile';
  static const _localUserName = 'Leitor';
  static const _localUserEmail = 'local@minha-estante.app';
  static const _localUserPassword = '12345678';
  static const _legacyLocalUserId = 'demo_giovane';

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<AppUser> _ensureLocalUser() async {
    final savedId = LocalStorageService.getCurrentUserId();
    if (savedId != null) {
      final savedUser = LocalStorageService.getUserById(savedId);
      if (savedUser != null) return AppUser.fromJson(savedUser);
    }

    final legacyUser = LocalStorageService.getUserById(_legacyLocalUserId);
    if (legacyUser != null) {
      final user = AppUser.fromJson(legacyUser);
      await LocalStorageService.setCurrentUserId(user.id);
      return user;
    }

    final existing = LocalStorageService.getUserByEmail(_localUserEmail);
    if (existing != null) {
      final user = AppUser.fromJson(existing);
      await LocalStorageService.setCurrentUserId(user.id);
      return user;
    }

    final user = AppUser(
      id: _localUserId,
      name: _localUserName,
      email: _localUserEmail,
      passwordHash: _hashPassword(_localUserPassword),
      createdAt: DateTime.now(),
    );

    await LocalStorageService.saveUser(user.toJson());
    await LocalStorageService.setCurrentUserId(user.id);
    return user;
  }

  @override
  Future<AppUser> enterAsGuest() => _ensureLocalUser();

  @override
  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    await _ensureLocalUser();

    final userData = LocalStorageService.getUserByEmail(email.toLowerCase());
    if (userData == null) {
      throw Exception('Usuario nao encontrado com este e-mail.');
    }

    final user = AppUser.fromJson(userData);
    final hash = _hashPassword(password);
    if (user.passwordHash != hash) {
      throw Exception('Senha incorreta.');
    }

    await LocalStorageService.setCurrentUserId(user.id);
    return user;
  }

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    final existing = LocalStorageService.getUserByEmail(email.toLowerCase());
    if (existing != null) {
      throw Exception('Ja existe uma conta com este e-mail.');
    }

    final user = AppUser(
      id: _uuid.v4(),
      name: name.trim(),
      email: email.toLowerCase().trim(),
      passwordHash: _hashPassword(password),
      createdAt: DateTime.now(),
    );

    await LocalStorageService.saveUser(user.toJson());
    await LocalStorageService.setCurrentUserId(user.id);
    return user;
  }

  @override
  Future<void> logout() async {
    await LocalStorageService.setCurrentUserId(null);
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    final savedId = LocalStorageService.getCurrentUserId();
    if (savedId != null) {
      final userData = LocalStorageService.getUserById(savedId);
      if (userData != null) return AppUser.fromJson(userData);
    }
    return null;
  }

  @override
  Future<AppUser> updateProfile({
    required String userId,
    required String name,
  }) async {
    final userData = LocalStorageService.getUserById(userId);
    if (userData == null) throw Exception('Usuario nao encontrado.');
    final user = AppUser.fromJson(userData).copyWith(name: name.trim());
    await LocalStorageService.saveUser(user.toJson());
    return user;
  }

  @override
  Future<void> updatePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final userData = LocalStorageService.getUserById(userId);
    if (userData == null) throw Exception('Usuario nao encontrado.');
    final user = AppUser.fromJson(userData);
    if (user.passwordHash != _hashPassword(oldPassword)) {
      throw Exception('Senha atual incorreta.');
    }
    final updatedUser = user.copyWith(passwordHash: _hashPassword(newPassword));
    await LocalStorageService.saveUser(updatedUser.toJson());
  }
}
