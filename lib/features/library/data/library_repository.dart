import '../domain/library_item.dart';
import '../domain/local_folder_import.dart';
import '../domain/local_folder_source.dart';
import '../domain/reading_progress.dart';

abstract class LibraryRepository {
  Future<List<LibraryItem>> getItems(String userId);
  Future<void> saveItems(String userId, List<LibraryItem> items);
  Future<void> addItem(String userId, LibraryItem item);
  Future<void> removeItem(String userId, String itemId);
  Future<void> updateItem(String userId, LibraryItem item);
  Future<void> markItemSeen(String userId, String itemId);
  Future<void> markItemOpened(String userId, String itemId);
  Future<void> toggleFavorite(String userId, String itemId);
  Future<void> updateStatus(
    String userId,
    String itemId,
    LibraryItemStatus status,
  );
  Future<List<LocalFolderSource>> getLocalFolders(String userId);
  Future<LocalFolderSyncResult> addLocalFolder(String userId, String path);
  Future<LocalFolderSyncResult> addLocalFolderImport(
    String userId,
    LocalFolderImport import,
  );
  Future<LocalFolderSyncResult> syncLocalFolders(String userId);
  Future<void> saveProgress(String userId, ReadingProgress progress);
  Future<ReadingProgress?> getProgress(String userId, String itemId);
  Future<List<ReadingProgress>> getAllProgress(String userId);
}
