import '../domain/app_user.dart';

abstract class AuthRepository {
  Future<AppUser> login({required String email, required String password});
  Future<AppUser> register({
    required String name,
    required String email,
    required String password,
  });
  Future<void> logout();
  Future<AppUser?> getCurrentUser();
  Future<AppUser> updateProfile({required String userId, required String name});
  Future<void> updatePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  });
}
