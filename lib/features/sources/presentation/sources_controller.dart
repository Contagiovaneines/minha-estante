import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_source.dart';
import '../../library/presentation/library_controller.dart';
import '../data/drive_public_api_service.dart';
import '../data/sources_repository.dart';
import '../../../core/utils/drive_link_parser.dart';

final sourcesRepositoryProvider = Provider<SourcesRepository>(
  (ref) => LocalSourcesRepository(),
);

final driveApiServiceProvider = Provider<DrivePublicApiService>(
  (ref) => DrivePublicApiService(),
);

final sourcesControllerProvider =
    AsyncNotifierProvider<SourcesController, List<LibrarySource>>(
      SourcesController.new,
    );

class SourcesController extends AsyncNotifier<List<LibrarySource>> {
  final _uuid = const Uuid();

  @override
  Future<List<LibrarySource>> build() async {
    final user = ref.watch(authControllerProvider).value;
    if (user == null) return [];
    final repo = ref.read(sourcesRepositoryProvider);
    return repo.getSources(user.id);
  }

  Future<void> refresh() async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(sourcesRepositoryProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => repo.getSources(user.id));
  }

  Future<String?> addSource({required String name, required String url}) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return 'Usuário não autenticado.';

    if (!DriveLinkParser.isValidDriveUrl(url)) {
      return 'Link do Drive inválido. Use um link de pasta ou arquivo público do Google Drive.';
    }

    final driveId = DriveLinkParser.extractId(url);
    if (driveId == null) {
      return 'Não foi possível extrair o ID do Drive. Verifique o link.';
    }

    final isFolder = DriveLinkParser.isFolder(url);
    final repo = ref.read(sourcesRepositoryProvider);

    final source = LibrarySource(
      id: _uuid.v4(),
      userId: user.id,
      name: name.trim(),
      originalUrl: url.trim(),
      driveId: driveId,
      sourceType: isFolder ? SourceType.folder : SourceType.file,
      createdAt: DateTime.now(),
    );

    await repo.addSource(source);

    final syncError = await syncSource(source);
    await refresh();

    return syncError;
  }

  Future<String?> syncSource(LibrarySource source) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return 'Usuário não autenticado.';

    final driveService = ref.read(driveApiServiceProvider);

    if (!driveService.hasApiKey) {
      return driveService.getFriendlyError('API_KEY_MISSING');
    }

    try {
      final items = await driveService.syncSource(
        userId: user.id,
        sourceId: source.id,
        driveId: source.driveId,
        isFolder: source.sourceType == SourceType.folder,
      );

      await ref.read(libraryControllerProvider.notifier).addItems(items);

      final repo = ref.read(sourcesRepositoryProvider);
      await repo.updateSource(
        source.copyWith(itemCount: items.length, lastSyncedAt: DateTime.now()),
      );

      await refresh();
      return null;
    } catch (e) {
      final code = e.toString().replaceFirst('Exception: ', '');
      return driveService.getFriendlyError(code);
    }
  }

  Future<void> removeSource(String sourceId) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;
    final repo = ref.read(sourcesRepositoryProvider);
    await repo.removeSource(user.id, sourceId);
    await ref
        .read(libraryControllerProvider.notifier)
        .removeItemsBySource(sourceId);
    await refresh();
  }

  Future<void> updateSourceName({
    required LibrarySource source,
    required String name,
  }) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;

    final repo = ref.read(sourcesRepositoryProvider);
    await repo.updateSource(source.copyWith(name: name.trim()));
    await refresh();
  }
}
