import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../data/library_repository.dart';
import '../data/local_library_repository.dart';
import '../domain/library_item.dart';
import '../domain/local_folder_import.dart';
import '../domain/local_folder_source.dart';
import '../domain/reading_progress.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LocalLibraryRepository(),
);

final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, List<LibraryItem>>(
      LibraryController.new,
    );

class LibraryController extends AsyncNotifier<List<LibraryItem>> {
  @override
  Future<List<LibraryItem>> build() async {
    final user = ref.watch(authControllerProvider).value;
    if (user == null) return [];
    final repo = ref.read(libraryRepositoryProvider);
    return repo.getItems(user.id);
  }

  Future<void> refresh() async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => repo.getItems(user.id));
  }

  Future<void> addItem(LibraryItem item) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    await repo.addItem(user.id, item);
    await refresh();
  }

  Future<void> addItems(List<LibraryItem> items) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    for (final item in items) {
      await repo.addItem(user.id, item);
    }
    await refresh();
  }

  Future<void> updateItem(LibraryItem item) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    await repo.updateItem(user.id, item);
    await refresh();
  }

  Future<LocalFolderSyncResult?> addLocalFolder(String path) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return null;
    final repo = ref.read(libraryRepositoryProvider);
    final result = await repo.addLocalFolder(user.id, path);
    await refresh();
    return result;
  }

  Future<LocalFolderSyncResult?> addLocalFolderImport(
    LocalFolderImport import,
  ) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return null;
    final repo = ref.read(libraryRepositoryProvider);
    final result = await repo.addLocalFolderImport(user.id, import);
    await refresh();
    return result;
  }

  Future<LocalFolderSyncResult?> syncLocalFolders() async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return null;
    final repo = ref.read(libraryRepositoryProvider);
    final result = await repo.syncLocalFolders(user.id);
    await refresh();
    return result;
  }

  Future<void> removeItem(String itemId) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    await repo.removeItem(user.id, itemId);
    await refresh();
  }

  Future<void> markItemSeen(String itemId) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    await repo.markItemSeen(user.id, itemId);
    final current = state.value;
    if (current == null) {
      await refresh();
      return;
    }
    state = AsyncData([
      for (final item in current)
        item.id == itemId ? item.copyWith(isNew: false) : item,
    ]);
  }

  Future<void> markItemOpened(String itemId) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    await repo.markItemOpened(user.id, itemId);
    final current = state.value;
    if (current == null) {
      await refresh();
      return;
    }

    state = AsyncData([
      for (final item in current)
        item.id == itemId
            ? item.copyWith(
                isNew: false,
                status: item.status == LibraryItemStatus.finished
                    ? LibraryItemStatus.finished
                    : LibraryItemStatus.reading,
                updatedAt: DateTime.now(),
              )
            : item,
    ]);
  }

  Future<void> toggleFavorite(String itemId) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    await repo.toggleFavorite(user.id, itemId);
    final current = state.value;
    if (current == null) {
      await refresh();
      return;
    }
    state = AsyncData([
      for (final item in current)
        item.id == itemId
            ? item.copyWith(
                isFavorite: !item.isFavorite,
                updatedAt: DateTime.now(),
              )
            : item,
    ]);
  }

  Future<void> updateStatus(String itemId, LibraryItemStatus status) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    await repo.updateStatus(user.id, itemId, status);
    final current = state.value;
    if (current == null) {
      await refresh();
      return;
    }
    state = AsyncData([
      for (final item in current)
        item.id == itemId
            ? item.copyWith(status: status, updatedAt: DateTime.now())
            : item,
    ]);
  }

  Future<void> removeItemsBySource(String sourceId) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    final items = await repo.getItems(user.id);
    final toRemove = items.where((e) => e.sourceId == sourceId).toList();
    for (final item in toRemove) {
      await repo.removeItem(user.id, item.id);
    }
    await refresh();
  }

  Future<void> saveProgress(ReadingProgress progress) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    await repo.saveProgress(user.id, progress);
    await refresh();
  }

  Future<ReadingProgress?> getProgress(String itemId) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return null;
    final repo = ref.read(libraryRepositoryProvider);
    return repo.getProgress(user.id, itemId);
  }

  LibraryItem? getItemById(String id) {
    return state.value?.firstWhere(
      (e) => e.id == id,
      orElse: () => throw Exception('Item não encontrado'),
    );
  }
}
