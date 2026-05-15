import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/local_storage_service.dart';
import '../domain/app_user.dart';
import 'auth_repository.dart';

class MockAuthRepository implements AuthRepository {
  final _uuid = const Uuid();
  static const _demoUserId = 'demo_giovane';
  static const _demoUserName = 'Giovane';
  static const _demoUserEmail = 'giovane@gmail.com';
  static const _demoUserPassword = '12345678';

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _ensureDemoUser() async {
    final existing = LocalStorageService.getUserByEmail(_demoUserEmail);
    if (existing != null) return;

    final user = AppUser(
      id: _demoUserId,
      name: _demoUserName,
      email: _demoUserEmail,
      passwordHash: _hashPassword(_demoUserPassword),
      createdAt: DateTime.now(),
    );

    await LocalStorageService.saveUser(user.toJson());
  }

  @override
  Future<AppUser> login({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    await _ensureDemoUser();

    final userData = LocalStorageService.getUserByEmail(email.toLowerCase());
    if (userData == null) {
      throw Exception('Usuário não encontrado com este e-mail.');
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
      throw Exception('Já existe uma conta com este e-mail.');
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
    final id = LocalStorageService.getCurrentUserId();
    if (id == null) return null;
    final userData = LocalStorageService.getUserById(id);
    if (userData == null) return null;
    return AppUser.fromJson(userData);
  }

  @override
  Future<AppUser> updateProfile({
    required String userId,
    required String name,
  }) async {
    final userData = LocalStorageService.getUserById(userId);
    if (userData == null) throw Exception('Usuário não encontrado.');
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
    if (userData == null) throw Exception('Usuário não encontrado.');
    final user = AppUser.fromJson(userData);
    if (user.passwordHash != _hashPassword(oldPassword)) {
      throw Exception('Senha atual incorreta.');
    }
    final updatedUser = user.copyWith(passwordHash: _hashPassword(newPassword));
    await LocalStorageService.saveUser(updatedUser.toJson());
  }
}
