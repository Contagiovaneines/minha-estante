import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/home_widget_service.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../../core/storage/saf_file_resolver.dart';
import 'android_saf_import_service.dart';
import '../domain/library_item.dart';
import '../domain/local_folder_import.dart';
import '../domain/local_folder_source.dart';
import '../domain/library_metadata_service.dart';
import '../domain/reading_progress.dart';
import 'library_repository.dart';
import '../../reader/domain/cbr_to_cbz_converter_service.dart';

class LocalLibraryRepository implements LibraryRepository {
  final LibraryMetadataService _metadataService = LibraryMetadataService();

  static const _supportedExtensions = {
    'cbr',
    'cbz',
    'cb7',
    'cbt',
    'cba',
    'pdf',
    'epub',
    'azw',
    'azw3',
    'kfx',
    'mobi',
    'doc',
    'docx',
    'txt',
    'mp3',
    'm4a',
    'm4b',
    'aac',
    'wav',
    'opus',
    'jpg',
    'jpeg',
    'png',
    'webp',
  };

  String _stableId(String prefix, String value) {
    final digest = sha1.convert(utf8.encode(value.toLowerCase())).toString();
    return '${prefix}_$digest';
  }

  bool _isSupportedFilePath(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return _supportedExtensions.contains(ext);
  }

  String _duplicateKey(String title) {
    return title.trim().toLowerCase();
  }

  bool _hasSameTitle(LibraryItem a, LibraryItem b) {
    return _duplicateKey(a.title) == _duplicateKey(b.title) &&
        (a.collectionId ?? '') == (b.collectionId ?? '');
  }

  String _duplicateItemKey(String? collectionId, String title) {
    // Agora incluímos o collectionId na chave para permitir arquivos com mesmo nome
    // em pastas (coleções) diferentes.
    return '${collectionId ?? 'root'}_${title.trim().toLowerCase()}';
  }

  ItemType _typeFromPath(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (ext == 'mp3' ||
        ext == 'm4a' ||
        ext == 'm4b' ||
        ext == 'aac' ||
        ext == 'wav' ||
        ext == 'opus') {
      return ItemType.audio;
    }
    if (ext == 'cbz' ||
        ext == 'cbr' ||
        ext == 'cb7' ||
        ext == 'cbt' ||
        ext == 'cba') {
      return ItemType.hq;
    }
    if (ext == 'epub' ||
        ext == 'mobi' ||
        ext == 'azw' ||
        ext == 'azw3' ||
        ext == 'kfx') {
      return ItemType.ebook;
    }
    if (ext == 'txt') return ItemType.text;
    if (ext == 'doc' || ext == 'docx') return ItemType.document;
    return ItemType.pdf;
  }

  String _collectionId(String sourceId, String collectionName) {
    return _stableId('collection', '$sourceId/$collectionName');
  }

  List<String> _relativeSegments(String relativePath) {
    return relativePath
        .split(RegExp(r'[\\/]'))
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
  }

  ({String id, String name}) _collectionForRelativePath({
    required LocalFolderSource folder,
    required String relativePath,
  }) {
    final segments = _relativeSegments(relativePath);
    final name = segments.length > 1 ? segments.first : folder.name;
    return (id: _collectionId(folder.id, name), name: name);
  }

  LibraryItem _itemFromFile({
    required String userId,
    required File file,
    required String sourceId,
    required String collectionId,
    required String collectionName,
    required String relativePath,
    LibraryItem? existing,
  }) {
    final stat = file.statSync();
    final updatedAt = existing == null ? DateTime.now() : stat.modified;

    return LibraryItem(
      id: _stableId('local', file.path),
      userId: userId,
      sourceId: sourceId,
      title: p.basenameWithoutExtension(file.path),
      author: existing?.author,
      description: existing?.description,
      collectionId: collectionId,
      collectionName: collectionName,
      relativePath: relativePath,
      type: _typeFromPath(file.path),
      origin: ItemOrigin.local,
      localPath: file.path,
      currentPage: existing?.currentPage ?? 0,
      totalPages: existing?.totalPages ?? 0,
      progress: existing?.progress ?? 0.0,
      durationSeconds: existing?.durationSeconds,
      positionSeconds: existing?.positionSeconds,
      isNew: existing?.isNew ?? true,
      isFavorite: existing?.isFavorite ?? false,
      status: existing?.status ?? LibraryItemStatus.toRead,
      createdAt: existing?.createdAt ?? updatedAt,
      updatedAt: updatedAt,
    );
  }

  LibraryItem _itemFromImportedFile({
    required String userId,
    required LocalFolderImportedFile file,
    required String sourceId,
    required String collectionId,
    required String collectionName,
    LibraryItem? existing,
  }) {
    final modifiedAt = file.modifiedMillis != null && file.modifiedMillis! > 0
        ? DateTime.fromMillisecondsSinceEpoch(file.modifiedMillis!)
        : DateTime.now();
    final catalogedAt = DateTime.now();

    return LibraryItem(
      id: _stableId('local', file.path),
      userId: userId,
      sourceId: sourceId,
      title: p.basenameWithoutExtension(file.name),
      author: existing?.author,
      description: existing?.description,
      collectionId: collectionId,
      collectionName: collectionName,
      relativePath: file.relativePath ?? file.name,
      type: _typeFromPath(file.name),
      origin: ItemOrigin.local,
      localPath: file.path,
      currentPage: existing?.currentPage ?? 0,
      totalPages: existing?.totalPages ?? 0,
      progress: existing?.progress ?? 0.0,
      durationSeconds: existing?.durationSeconds,
      positionSeconds: existing?.positionSeconds,
      isNew: existing?.isNew ?? true,
      isFavorite: existing?.isFavorite ?? false,
      status: existing?.status ?? LibraryItemStatus.toRead,
      createdAt: existing?.createdAt ?? catalogedAt,
      updatedAt: existing == null ? catalogedAt : modifiedAt,
    );
  }

  @override
  Future<List<LibraryItem>> getItems(String userId) async {
    final stored = LocalStorageService.getItems(userId);
    if (stored.isEmpty) return [];

    final items = stored.map(LibraryItem.fromJson).toList();
    final mockItems = items
        .where((item) => item.id.startsWith('mock_'))
        .toList();
    final realItems = items
        .where((item) => !item.id.startsWith('mock_'))
        .toList();
    if (mockItems.isNotEmpty) {
      await saveItems(userId, realItems);
      for (final item in mockItems) {
        await LocalStorageService.clearItemState(userId, item.id);
      }
    }
    return realItems;
  }

  @override
  Future<void> saveItems(String userId, List<LibraryItem> items) async {
    await LocalStorageService.saveItems(
      userId,
      items.map((e) => e.toJson()).toList(),
    );
  }

  @override
  Future<void> addItem(String userId, LibraryItem item) async {
    final items = await getItems(userId);
    final enrichedItem = await _metadataService.enrich(item);
    final exists = items.any(
      (e) => e.id == enrichedItem.id || _hasSameTitle(e, enrichedItem),
    );
    if (!exists) {
      items.add(enrichedItem);
      await saveItems(userId, items);
    }
  }

  @override
  Future<void> removeItem(String userId, String itemId) async {
    final items = await getItems(userId);
    items.removeWhere((e) => e.id == itemId);
    await saveItems(userId, items);
    await LocalStorageService.clearItemState(userId, itemId);
    if (LocalStorageService.getLastOpenedItemId(userId) == itemId) {
      await LocalStorageService.clearLastOpenedItemId(userId);
      await HomeWidgetService.clear();
    }
  }

  @override
  Future<void> updateItem(String userId, LibraryItem item) async {
    final items = await getItems(userId);
    final idx = items.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      items[idx] = item;
      await saveItems(userId, items);
    }
  }

  @override
  Future<void> markItemSeen(String userId, String itemId) async {
    final items = await getItems(userId);
    final idx = items.indexWhere((e) => e.id == itemId);
    if (idx >= 0 && items[idx].isNew) {
      items[idx] = items[idx].copyWith(isNew: false);
      await saveItems(userId, items);
    }
  }

  @override
  Future<void> markItemOpened(String userId, String itemId) async {
    final items = await getItems(userId);
    final idx = items.indexWhere((e) => e.id == itemId);
    if (idx < 0) return;

    final item = items[idx];
    await LocalStorageService.saveLastOpenedItemId(userId, itemId);
    items[idx] = item.copyWith(
      isNew: false,
      status: item.status == LibraryItemStatus.finished
          ? LibraryItemStatus.finished
          : LibraryItemStatus.reading,
      updatedAt: DateTime.now(),
    );
    await saveItems(userId, items);
    await HomeWidgetService.updateFromItem(items[idx]);
  }

  @override
  Future<void> toggleFavorite(String userId, String itemId) async {
    final items = await getItems(userId);
    final idx = items.indexWhere((e) => e.id == itemId);
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(
        isFavorite: !items[idx].isFavorite,
        updatedAt: DateTime.now(),
      );
      await saveItems(userId, items);
    }
  }

  @override
  Future<void> updateStatus(
    String userId,
    String itemId,
    LibraryItemStatus status,
  ) async {
    final items = await getItems(userId);
    final idx = items.indexWhere((e) => e.id == itemId);
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(
        status: status,
        updatedAt: DateTime.now(),
      );
      await saveItems(userId, items);
    }
  }

  @override
  Future<List<LocalFolderSource>> getLocalFolders(String userId) async {
    final raw = LocalStorageService.getLocalFolders(userId);
    return raw.map(LocalFolderSource.fromJson).toList();
  }

  Future<void> _saveLocalFolders(
    String userId,
    List<LocalFolderSource> folders,
  ) async {
    await LocalStorageService.saveLocalFolders(
      userId,
      folders.map((folder) => folder.toJson()).toList(),
    );
  }

  @override
  Future<LocalFolderSyncResult> addLocalFolder(
    String userId,
    String path,
  ) async {
    final directory = Directory(path);
    if (!directory.existsSync() || path.trim() == '/') {
      throw Exception(
        'Não foi possível acessar essa pasta. Selecione outra pasta ou adicione os arquivos manualmente.',
      );
    }

    final folders = await getLocalFolders(userId);
    final id = _stableId('local_folder', path);
    final existingIndex = folders.indexWhere((folder) => folder.id == id);

    if (existingIndex < 0) {
      folders.add(
        LocalFolderSource(
          id: id,
          userId: userId,
          name: p.basename(path).isEmpty ? 'Pasta local' : p.basename(path),
          path: path,
          createdAt: DateTime.now(),
        ),
      );
      await _saveLocalFolders(userId, folders);
    }

    return syncLocalFolders(userId);
  }

  @override
  Future<LocalFolderSyncResult> addLocalFolderImport(
    String userId,
    LocalFolderImport import,
  ) async {
    final folders = await getLocalFolders(userId);
    final id = _stableId('local_folder', import.path);
    final existingIndex = folders.indexWhere((folder) => folder.id == id);
    final source = existingIndex >= 0
        ? folders[existingIndex].copyWith(name: import.name)
        : LocalFolderSource(
            id: id,
            userId: userId,
            name: import.name,
            path: import.path,
            createdAt: DateTime.now(),
          );

    if (existingIndex >= 0) {
      folders[existingIndex] = source;
    } else {
      folders.add(source);
    }
    await _saveLocalFolders(userId, folders);

    return _mergeImportedFolder(userId: userId, folder: source, import: import);
  }

  Future<LocalFolderSyncResult> _mergeImportedFolder({
    required String userId,
    required LocalFolderSource folder,
    required LocalFolderImport import,
  }) async {
    var items = await getItems(userId);
    var added = 0;
    var duplicates = 0;
    final duplicateTitles = <String>[];
    final errors = <String>[];

    final existingById = {
      for (final item in items.where(
        (item) => item.origin == ItemOrigin.local && item.sourceId == folder.id,
      ))
        item.id: item,
    };
    final existingOutsideFolderKeys = {
      for (final item in items.where((item) => item.sourceId != folder.id))
        _duplicateItemKey(item.collectionId, item.title),
    };
    final scannedKeys = <String>{};
    final scannedItems = <LibraryItem>[];
    var pdfAdded = 0;
    var cbzAdded = 0;
    var cbrConverted = 0;
    var cbrFailed = 0;
    var ignored = 0;

    // First pass: identify all CBZ/PDF titles to avoid redundant CBR conversions
    final existingTitles = <String>{};
    for (final file in import.files) {
      final ext = p.extension(file.name).replaceFirst('.', '').toLowerCase();
      if (ext == 'cbz' || ext == 'pdf') {
        existingTitles.add(p.basenameWithoutExtension(file.name).toLowerCase());
      }
    }

    // ── CBR: converte para CBZ e usa o arquivo convertido ──
    for (var i = 0; i < import.files.length; i++) {
      final file = import.files[i];
      final ext = p.extension(file.name).replaceFirst('.', '').toLowerCase();

      if (!_isSupportedFilePath(file.name)) {
        ignored++;
        continue;
      }

      if (ext == 'cbr' || ext == 'rar') {
        final titleWithoutExt = p.basenameWithoutExtension(file.name);
        if (existingTitles.contains(titleWithoutExt.toLowerCase())) {
          ignored++;
          continue;
        }

        // Reporta progresso da conversão
        AndroidSafImportService.reportProgress(
          LocalFolderImportProgress(
            current: i + 1,
            total: import.files.length,
            fileName: file.name,
            phase: 'converting',
          ),
        );

        try {
          // Resolve o arquivo para processamento (copia URI SAF para cache se necessário)
          final resolvedFile = await SafFileResolver.resolveForProcessing(
            file.path,
          );

          final cbzFile = await CbrToCbzConverterService().convertCbrToCbz(
            resolvedFile,
          );
          final relativePath = file.relativePath ?? file.name;
          final collection = _collectionForRelativePath(
            folder: folder,
            relativePath: relativePath,
          );
          final itemId = _stableId('local_cbr', file.path);
          final existing = existingById[itemId];
          final now = DateTime.now();
          final item = await _metadataService.enrich(
            LibraryItem(
              id: itemId,
              userId: userId,
              sourceId: folder.id,
              title: titleWithoutExt,
              collectionId: collection.id,
              collectionName: collection.name,
              relativePath: relativePath,
              type: ItemType.hq,
              origin: ItemOrigin.local,
              localPath: cbzFile.path,
              currentPage: existing?.currentPage ?? 0,
              totalPages: existing?.totalPages ?? 0,
              progress: existing?.progress ?? 0.0,
              isNew: existing?.isNew ?? true,
              isFavorite: existing?.isFavorite ?? false,
              status: existing?.status ?? LibraryItemStatus.toRead,
              createdAt: existing?.createdAt ?? now,
              updatedAt: existing == null ? now : now,
            ),
          );

          final key = _duplicateItemKey(item.collectionId, item.title);
          if (existingOutsideFolderKeys.contains(key) ||
              scannedKeys.contains(key)) {
            duplicates++;
            if (!duplicateTitles.contains(item.title)) {
              duplicateTitles.add(item.title);
            }
          } else {
            scannedKeys.add(key);
            scannedItems.add(item);
            if (!existingById.containsKey(itemId)) {
              added++;
              cbrConverted++;
            }
          }
        } catch (e) {
          cbrFailed++;
          errors.add(
            'Erro em "${file.name}": ${e.toString().replaceFirst('Exception: ', '')}',
          );
        }
        continue;
      }

      final relativePath = file.relativePath ?? file.name;
      final collection = _collectionForRelativePath(
        folder: folder,
        relativePath: relativePath,
      );
      final itemId = _stableId('local', file.path);
      final item = await _metadataService.enrich(
        _itemFromImportedFile(
          userId: userId,
          file: file,
          sourceId: folder.id,
          collectionId: collection.id,
          collectionName: collection.name,
          existing: existingById[itemId],
        ),
      );
      final key = _duplicateItemKey(item.collectionId, item.title);
      if (existingOutsideFolderKeys.contains(key) ||
          scannedKeys.contains(key)) {
        duplicates++;
        if (!duplicateTitles.contains(item.title)) {
          duplicateTitles.add(item.title);
        }
        continue;
      }

      scannedKeys.add(key);
      scannedItems.add(item);
      if (!existingById.containsKey(itemId)) {
        added++;
        if (ext == 'pdf') pdfAdded++;
        if (ext == 'cbz') cbzAdded++;
      }
    }

    items = [
      ...items.where((item) => item.sourceId != folder.id),
      ...scannedItems,
    ];
    await saveItems(userId, items);

    final folders = await getLocalFolders(userId);
    final folderIndex = folders.indexWhere((entry) => entry.id == folder.id);
    if (folderIndex >= 0) {
      folders[folderIndex] = folders[folderIndex].copyWith(
        itemCount: scannedItems.length,
        lastSyncedAt: DateTime.now(),
      );
      await _saveLocalFolders(userId, folders);
    }

    return LocalFolderSyncResult(
      added: added,
      total: scannedItems.length,
      duplicates: duplicates,
      duplicateTitles: duplicateTitles,
      errors: errors,
      pdfAdded: pdfAdded,
      cbzAdded: cbzAdded,
      cbrConverted: cbrConverted,
      cbrFailed: cbrFailed,
      ignored: ignored,
    );
  }

  @override
  Future<LocalFolderSyncResult> syncLocalFolders(String userId) async {
    final folders = await getLocalFolders(userId);
    if (folders.isEmpty) {
      return const LocalFolderSyncResult(added: 0, total: 0);
    }

    var items = await getItems(userId);
    var added = 0;
    var total = 0;
    var duplicates = 0;
    final duplicateTitles = <String>[];
    final errors = <String>[];
    final updatedFolders = <LocalFolderSource>[];
    final seenPaths = <String>{};
    var pdfAddedTotal = 0;
    var cbzAddedTotal = 0;
    var cbrConvertedTotal = 0;
    var cbrFailedTotal = 0;
    var ignoredTotal = 0;

    for (final folder in folders) {
      if (seenPaths.contains(folder.path)) {
        // Remove os itens da pasta duplicada do banco de dados
        items = items.where((item) => item.sourceId != folder.id).toList();
        continue;
      }
      seenPaths.add(folder.path);

      try {
        if (folder.path.startsWith('content://')) {
          final import = await AndroidSafImportService().syncFolder(
            folder.path,
          );
          final result = await _mergeImportedFolder(
            userId: userId,
            folder: folder,
            import: import,
          );
          added += result.added;
          total += result.total;
          duplicates += result.duplicates;
          duplicateTitles.addAll(result.duplicateTitles);
          updatedFolders.add(
            folder.copyWith(
              itemCount: result.total,
              lastSyncedAt: DateTime.now(),
            ),
          );
          items = await getItems(userId);
          continue;
        }

        final directory = Directory(folder.path);
        if (!directory.existsSync()) {
          errors.add('A pasta "${folder.name}" não está acessível.');
          updatedFolders.add(folder);
          continue;
        }

        final existingById = {
          for (final item in items.where(
            (item) =>
                item.origin == ItemOrigin.local && item.sourceId == folder.id,
          ))
            item.id: item,
        };
        final existingOutsideFolderKeys = {
          for (final item in items.where((item) => item.sourceId != folder.id))
            _duplicateItemKey(item.collectionId, item.title),
        };
        final scannedKeys = <String>{};
        final scannedItems = <LibraryItem>[];

        final entities = directory.listSync(
          recursive: true,
          followLinks: false,
        );

        // First pass: identify all CBZ/PDF titles to avoid redundant CBR conversions
        final existingTitles = <String>{};
        for (final entity in entities) {
          if (entity is! File) continue;
          final ext = p
              .extension(entity.path)
              .replaceFirst('.', '')
              .toLowerCase();
          if (ext == 'cbz' || ext == 'pdf') {
            existingTitles.add(
              p.basenameWithoutExtension(entity.path).toLowerCase(),
            );
          }
        }

        final allFiles = entities.whereType<File>().toList();
        for (var i = 0; i < allFiles.length; i++) {
          final entity = allFiles[i];

          final ext = p
              .extension(entity.path)
              .replaceFirst('.', '')
              .toLowerCase();

          // ── CBR: converte para CBZ e usa o arquivo convertido ──
          if (ext == 'cbr' || ext == 'rar') {
            final titleWithoutExt = p.basenameWithoutExtension(entity.path);
            if (existingTitles.contains(titleWithoutExt.toLowerCase())) {
              ignoredTotal++;
              continue;
            }

            // Reporta progresso da conversão
            AndroidSafImportService.reportProgress(
              LocalFolderImportProgress(
                current: i + 1,
                total: allFiles.length,
                fileName: p.basename(entity.path),
                phase: 'converting',
              ),
            );

            try {
              // Resolve o arquivo para processamento (copia URI SAF para cache se necessário)
              final resolvedFile = await SafFileResolver.resolveForProcessing(
                entity.path,
              );

              final cbzFile = await CbrToCbzConverterService().convertCbrToCbz(
                resolvedFile,
              );
              final relativePath = p.relative(entity.path, from: folder.path);
              final collection = _collectionForRelativePath(
                folder: folder,
                relativePath: relativePath,
              );
              final itemId = _stableId('local_cbr', entity.path);
              final existing = existingById[itemId];
              final now = DateTime.now();
              final item = await _metadataService.enrich(
                LibraryItem(
                  id: itemId,
                  userId: userId,
                  sourceId: folder.id,
                  title: titleWithoutExt,
                  collectionId: collection.id,
                  collectionName: collection.name,
                  relativePath: relativePath,
                  type: ItemType.hq,
                  origin: ItemOrigin.local,
                  localPath: cbzFile.path,
                  currentPage: existing?.currentPage ?? 0,
                  totalPages: existing?.totalPages ?? 0,
                  progress: existing?.progress ?? 0.0,
                  isNew: existing?.isNew ?? true,
                  isFavorite: existing?.isFavorite ?? false,
                  status: existing?.status ?? LibraryItemStatus.toRead,
                  createdAt: existing?.createdAt ?? now,
                  updatedAt: existing == null ? now : now,
                ),
              );
              final key = _duplicateItemKey(item.collectionId, item.title);
              if (!existingOutsideFolderKeys.contains(key) &&
                  !scannedKeys.contains(key)) {
                scannedKeys.add(key);
                scannedItems.add(item);
                if (!existingById.containsKey(itemId)) {
                  added++;
                  cbrConvertedTotal++;
                }
              } else {
                duplicates++;
                if (!duplicateTitles.contains(item.title)) {
                  duplicateTitles.add(item.title);
                }
              }
            } catch (e) {
              cbrFailedTotal++;
              errors.add(
                'Erro ao converter "${p.basename(entity.path)}": ${e.toString().replaceFirst('Exception: ', '')}',
              );
            }
            continue;
          }

          // ── Outros formatos suportados ─────────────────────────
          if (!_isSupportedFilePath(entity.path)) {
            ignoredTotal++;
            continue;
          }

          final relativePath = p.relative(entity.path, from: folder.path);
          final collection = _collectionForRelativePath(
            folder: folder,
            relativePath: relativePath,
          );
          final itemId = _stableId('local', entity.path);
          final item = await _metadataService.enrich(
            _itemFromFile(
              userId: userId,
              file: entity,
              sourceId: folder.id,
              collectionId: collection.id,
              collectionName: collection.name,
              relativePath: relativePath,
              existing: existingById[itemId],
            ),
          );
          final key = _duplicateItemKey(item.collectionId, item.title);
          if (existingOutsideFolderKeys.contains(key) ||
              scannedKeys.contains(key)) {
            duplicates++;
            if (!duplicateTitles.contains(item.title)) {
              duplicateTitles.add(item.title);
            }
            continue;
          }

          scannedKeys.add(key);
          scannedItems.add(item);
          if (!existingById.containsKey(itemId)) {
            added++;
            if (ext == 'pdf') pdfAddedTotal++;
            if (ext == 'cbz') cbzAddedTotal++;
          }
        }

        items = [
          ...items.where((item) => item.sourceId != folder.id),
          ...scannedItems,
        ];
        total += scannedItems.length;
        updatedFolders.add(
          folder.copyWith(
            itemCount: scannedItems.length,
            lastSyncedAt: DateTime.now(),
          ),
        );
      } catch (_) {
        errors.add(
          'Não foi possível ler a pasta "${folder.name}". Tente selecionar os arquivos manualmente.',
        );
        updatedFolders.add(folder);
      }
    }

    await saveItems(userId, items);
    await _saveLocalFolders(userId, updatedFolders);

    return LocalFolderSyncResult(
      added: added,
      total: total,
      duplicates: duplicates,
      duplicateTitles: duplicateTitles,
      errors: errors,
      pdfAdded: pdfAddedTotal,
      cbzAdded: cbzAddedTotal,
      cbrConverted: cbrConvertedTotal,
      cbrFailed: cbrFailedTotal,
      ignored: ignoredTotal,
    );
  }

  @override
  Future<void> saveProgress(String userId, ReadingProgress progress) async {
    await LocalStorageService.saveProgress(userId, progress.toJson());
    final items = await getItems(userId);
    final idx = items.indexWhere((e) => e.id == progress.itemId);
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(
        currentPage: progress.currentPage,
        totalPages: progress.totalPages,
        progress: progress.percent,
        positionSeconds: progress.positionSeconds,
        status: progress.percent >= 1.0
            ? LibraryItemStatus.finished
            : LibraryItemStatus.reading,
        updatedAt: DateTime.now(),
      );
      await saveItems(userId, items);
      await HomeWidgetService.updateFromItem(items[idx]);
    }
  }

  @override
  Future<ReadingProgress?> getProgress(String userId, String itemId) async {
    final raw = LocalStorageService.getProgress(userId, itemId);
    if (raw == null) return null;
    return ReadingProgress.fromJson(raw);
  }

  @override
  Future<List<ReadingProgress>> getAllProgress(String userId) async {
    final all = LocalStorageService.getAllProgress(userId);
    return all.map(ReadingProgress.fromJson).toList();
  }
}
