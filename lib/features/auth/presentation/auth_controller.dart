import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/local_auth_repository.dart';
import '../domain/app_user.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => LocalAuthRepository(),
);

final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final repo = ref.read(authRepositoryProvider);
    return repo.getCurrentUser();
  }

  Future<void> enterAsGuest() async {
    final repo = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(repo.enterAsGuest);
  }

  Future<void> login({required String email, required String password}) async {
    final repo = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => repo.login(email: email, password: password),
    );
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => repo.register(name: name, email: email, password: password),
    );
  }

  Future<void> logout() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.logout();
    state = const AsyncData(null);
  }

  Future<void> updateProfile({required String name}) async {
    final user = state.value;
    if (user == null) return;
    final repo = ref.read(authRepositoryProvider);
    final updated = await repo.updateProfile(userId: user.id, name: name);
    state = AsyncData(updated);
  }

  Future<void> updatePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final user = state.value;
    if (user == null) return;
    final repo = ref.read(authRepositoryProvider);
    await repo.updatePassword(
      userId: user.id,
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
  }
}
