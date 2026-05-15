import '../../../core/storage/local_storage_service.dart';
import '../../library/domain/library_source.dart';

abstract class SourcesRepository {
  Future<List<LibrarySource>> getSources(String userId);
  Future<void> addSource(LibrarySource source);
  Future<void> updateSource(LibrarySource source);
  Future<void> removeSource(String userId, String sourceId);
}

class LocalSourcesRepository implements SourcesRepository {
  @override
  Future<List<LibrarySource>> getSources(String userId) async {
    final raw = LocalStorageService.getSources(userId);
    return raw.map(LibrarySource.fromJson).toList();
  }

  @override
  Future<void> addSource(LibrarySource source) async {
    final current = await getSources(source.userId);
    current.add(source);
    await LocalStorageService.saveSources(
      source.userId,
      current.map((e) => e.toJson()).toList(),
    );
  }

  @override
  Future<void> updateSource(LibrarySource source) async {
    final current = await getSources(source.userId);
    final idx = current.indexWhere((e) => e.id == source.id);
    if (idx >= 0) {
      current[idx] = source;
      await LocalStorageService.saveSources(
        source.userId,
        current.map((e) => e.toJson()).toList(),
      );
    }
  }

  @override
  Future<void> removeSource(String userId, String sourceId) async {
    final current = await getSources(userId);
    current.removeWhere((e) => e.id == sourceId);
    await LocalStorageService.saveSources(
      userId,
      current.map((e) => e.toJson()).toList(),
    );
  }
}
