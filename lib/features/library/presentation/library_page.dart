import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../../core/widgets/loading_view.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../reader/domain/cbr_to_cbz_converter_service.dart';
import '../../reader/domain/native_archive_service.dart';
import '../data/android_saf_import_service.dart';
import '../domain/library_collection.dart';
import '../domain/library_item.dart';
import '../domain/local_folder_import.dart';
import '../domain/local_folder_source.dart';
import 'library_controller.dart';
import 'library_view_filter.dart';
import 'widgets/book_grid_card.dart';
import 'widgets/continue_reading_card.dart';
import 'widgets/library_item_cover.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchController = TextEditingController();
  final _authorSearchController = TextEditingController();
  final _collectionSearchController = TextEditingController();
  StreamSubscription<LocalFolderImportProgress>? _importProgressSub;
  StreamSubscription<NativeOpenedArchive>? _openedArchiveSub;
  bool _isLocalImporting = false;
  bool _isMinimized = false;
  bool _isHandlingOpenedArchive = false;
  double? _importProgress;
  String _importMessage = 'Importando arquivos...';
  LibraryViewFilter _filter = LibraryViewFilter.all;
  LibraryTypeFilter _typeFilter = LibraryTypeFilter.all;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _authorSearchController.addListener(() => setState(() {}));
    _collectionSearchController.addListener(() => setState(() {}));
    if (AndroidSafImportService.isSupported) {
      _importProgressSub = AndroidSafImportService.progressStream.listen(
        _handleImportProgress,
      );
    }
    _openedArchiveSub = NativeArchiveService.openedArchiveStream.listen(
      _handleOpenedArchive,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final openedArchive = await NativeArchiveService()
          .consumeInitialOpenedArchive();
      if (openedArchive != null) {
        _handleOpenedArchive(openedArchive);
      }
    });
  }

  @override
  void dispose() {
    _importProgressSub?.cancel();
    _openedArchiveSub?.cancel();
    _searchController.dispose();
    _authorSearchController.dispose();
    _collectionSearchController.dispose();
    super.dispose();
  }

  void _handleImportProgress(LocalFolderImportProgress progress) {
    if (!mounted) return;
    setState(() {
      _importProgress = progress.percent;
      final fileName = progress.fileName;

      if (progress.phase == 'converting') {
        _importMessage = 'Convertendo ${fileName ?? 'arquivo'}...';
      } else {
        _importMessage = fileName == null || fileName.isEmpty
            ? 'Preparando importacao...'
            : 'Importando $fileName';
      }
    });
  }

  Future<void> _handleOpenedArchive(NativeOpenedArchive openedArchive) async {
    if (!mounted || _isHandlingOpenedArchive) return;

    final user = ref.read(authControllerProvider).value;
    if (user == null) return;

    _isHandlingOpenedArchive = true;
    try {
      final fileName = (openedArchive.name?.trim().isNotEmpty ?? false)
          ? openedArchive.name!.trim()
          : 'arquivo.cbr';
      final now = DateTime.now();
      final item = LibraryItem(
        id: 'opened_${const Uuid().v4()}',
        userId: user.id,
        title: p.basenameWithoutExtension(fileName).isEmpty
            ? 'HQ'
            : p.basenameWithoutExtension(fileName),
        collectionId: 'opened_${user.id}',
        collectionName: 'Abrir com',
        relativePath: fileName,
        type: ItemType.hq,
        origin: ItemOrigin.local,
        localPath: openedArchive.uri,
        isNew: false,
        createdAt: now,
        updatedAt: now,
      );

      if (!mounted) return;
      context.push('/hq_from_path', extra: item);
    } finally {
      _isHandlingOpenedArchive = false;
    }
  }

  Future<void> _pickLocalFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: _supportedExtensions,
    );

    if (result == null || result.files.isEmpty) return;

    final user = ref.read(authControllerProvider).value;
    if (user == null) return;

    final uuid = const Uuid();
    final selectedFiles = result.files
        .where((file) => file.path != null)
        .toList();
    final newItems = <LibraryItem>[];

    _startImportProgress(message: 'Preparando arquivo...', progress: null);
    try {
      for (final file in selectedFiles) {
        final ext = (file.extension ?? '').toLowerCase();
        var type = _itemTypeFromExtension(ext);
        var localPath = file.path!;
        var relativePath = file.name;

        if (ext == 'cbr' || ext == 'rar') {
          _updateImportProgress(
            message: 'Convertendo ${file.name}...',
            progress: null,
          );
          final cbzFile = await CbrToCbzConverterService().convertCbrToCbz(
            File(file.path!),
          );
          localPath = cbzFile.path;
          relativePath = '${p.basenameWithoutExtension(file.name)}.cbz';
          type = ItemType.hq;
        }

        final now = DateTime.now();
        const collectionName = 'Arquivos manuais';
        newItems.add(
          LibraryItem(
            id: uuid.v4(),
            userId: user.id,
            title: p.basenameWithoutExtension(file.name),
            collectionId: 'manual_${user.id}',
            collectionName: collectionName,
            relativePath: relativePath,
            type: type,
            origin: ItemOrigin.local,
            localPath: localPath,
            isNew: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    } catch (e) {
      _finishImportProgress();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (newItems.isEmpty) {
      _finishImportProgress();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível acessar o arquivo selecionado.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final currentItems = ref.read(libraryControllerProvider).value ?? [];
    final duplicates = newItems
        .where(
          (item) => currentItems.any(
            (existing) =>
                _duplicateItemKey(existing.collectionId, existing.title) ==
                _duplicateItemKey(item.collectionId, item.title),
          ),
        )
        .toList();
    final itemsToAdd = newItems
        .where(
          (item) => !duplicates.any(
            (duplicate) =>
                _duplicateItemKey(duplicate.collectionId, duplicate.title) ==
                _duplicateItemKey(item.collectionId, item.title),
          ),
        )
        .toList();

    if (duplicates.isNotEmpty) {
      _showDuplicateSnackBar(duplicates.map((item) => item.title).toList());
    }

    if (itemsToAdd.isEmpty) {
      _finishImportProgress();
      return;
    }

    _updateImportProgress(message: 'Adicionando arquivo...', progress: 0);
    await ref.read(libraryControllerProvider.notifier).addItems(itemsToAdd);
    _updateImportProgress(message: 'Arquivo adicionado.', progress: 1);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${itemsToAdd.length} arquivo adicionado à biblioteca.'),
        backgroundColor: AppColors.localAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
    _finishImportProgress();
  }

  Future<void> _pickLocalFolder() async {
    if (AndroidSafImportService.isSupported) {
      await _pickAndroidSafFolder();
      return;
    }

    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Selecionar pasta da biblioteca',
    );
    if (path == null) return;

    try {
      _startImportProgress(message: 'Preparando pasta...', progress: null);
      final result = await ref
          .read(libraryControllerProvider.notifier)
          .addLocalFolder(path);
      if (!mounted || result == null) return;
      _showLocalSyncSnackBar(result, prefix: 'Pasta adicionada.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _finishImportProgress();
    }
  }

  Future<void> _pickAndroidSafFolder() async {
    try {
      _startImportProgress(message: 'Abrindo seletor de pasta...', progress: 0);
      final import = await AndroidSafImportService().pickFolder();
      if (import == null) return;

      final result = await ref
          .read(libraryControllerProvider.notifier)
          .addLocalFolderImport(import);
      if (!mounted || result == null) return;
      _showLocalSyncSnackBar(result, prefix: 'Pasta adicionada.');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _finishImportProgress();
    }
  }

  Future<void> _syncLocalFolders({bool silent = false}) async {
    try {
      if (!silent) {
        _startImportProgress(message: 'Atualizando pastas...', progress: 0);
      }
      final result = await ref
          .read(libraryControllerProvider.notifier)
          .syncLocalFolders();
      if (!mounted || result == null || silent) return;
      _showLocalSyncSnackBar(result, prefix: 'Pastas atualizadas.');
    } catch (e) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (!silent) _finishImportProgress();
    }
  }

  void _startImportProgress({required String message, double? progress}) {
    if (!mounted) return;
    setState(() {
      _isLocalImporting = true;
      _isMinimized = false;
      _importMessage = message;
      _importProgress = progress;
    });
  }

  void _updateImportProgress({required String message, double? progress}) {
    if (!mounted) return;
    setState(() {
      _importMessage = message;
      _importProgress = progress;
    });
  }

  void _finishImportProgress() {
    if (!mounted) return;
    setState(() {
      _isLocalImporting = false;
      _isMinimized = false;
      _importProgress = null;
      _importMessage = 'Importando arquivos...';
    });
  }

  void _showLocalSyncSnackBar(
    LocalFolderSyncResult result, {
    required String prefix,
  }) {
    final message = _localSyncMessage(result, prefix: prefix);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: result.hasErrors
            ? AppColors.error
            : AppColors.localAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _localSyncMessage(
    LocalFolderSyncResult result, {
    required String prefix,
  }) {
    if (result.total == 0 && result.duplicates == 0 && result.errors.isEmpty) {
      return 'Nenhum arquivo compatível foi encontrado na pasta. No Android, algumas pastas não liberam acesso ao conteúdo; nesse caso selecione outra pasta ou adicione o arquivo manualmente.';
    }

    final List<String> parts = [];
    if (result.pdfAdded > 0) {
      parts.add('${result.pdfAdded} PDF(s)');
    }
    if (result.cbzAdded > 0) {
      parts.add('${result.cbzAdded} CBZ(s)');
    }
    if (result.cbrConverted > 0) {
      parts.add('${result.cbrConverted} CBR(s) convertidos');
    }

    String summary = parts.isNotEmpty
        ? '$prefix Adicionados: ${parts.join(', ')}.'
        : '$prefix Nenhum arquivo novo adicionado.';

    if (result.duplicates > 0) {
      summary += ' ${result.duplicates} já existiam.';
    }

    if (result.cbrFailed > 0) {
      summary += ' ${result.cbrFailed} CBR(s) falharam na conversão.';
    }

    if (result.ignored > 0) {
      summary += ' ${result.ignored} arquivo(s) ignorados.';
    }

    if (result.errors.isNotEmpty) {
      summary += '\n\nErro: ${result.errors.first}';
    }

    return summary;
  }

  String _shortTitleList(List<String> titles) {
    if (titles.isEmpty) return 'mesmo nome';
    final visible = titles.take(2).join(', ');
    final remaining = titles.length - 2;
    return remaining > 0 ? '$visible e mais $remaining' : visible;
  }

  String _duplicateKey(String title) => title.trim().toLowerCase();

  String _duplicateItemKey(String? collectionId, String title) {
    return '${collectionId ?? ''}/${_duplicateKey(title)}';
  }

  ItemType _itemTypeFromExtension(String extension) {
    if (extension == 'mp3' ||
        extension == 'm4a' ||
        extension == 'm4b' ||
        extension == 'aac' ||
        extension == 'wav' ||
        extension == 'opus') {
      return ItemType.audio;
    }
    if (extension == 'cbz' ||
        extension == 'cbr' ||
        extension == 'cb7' ||
        extension == 'cbt' ||
        extension == 'cba') {
      return ItemType.hq;
    }
    if (extension == 'epub' ||
        extension == 'mobi' ||
        extension == 'azw' ||
        extension == 'azw3' ||
        extension == 'kfx') {
      return ItemType.ebook;
    }
    if (extension == 'txt') return ItemType.text;
    if (extension == 'doc' || extension == 'docx') return ItemType.document;
    return ItemType.pdf;
  }

  static const _supportedExtensions = [
    'pdf',
    'epub',
    'cbr',
    'cbz',
    'cb7',
    'cbt',
    'cba',
    'azw',
    'azw3',
    'kfx',
    'mobi',
    'doc',
    'docx',
    'txt',
  ];

  static const _libraryTypeFilterOptions = [
    LibraryTypeFilter.all,
    LibraryTypeFilter.pdf,
    LibraryTypeFilter.hq,
    LibraryTypeFilter.ebook,
    LibraryTypeFilter.document,
  ];

  void _showDuplicateSnackBar(List<String> titles) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Já existe livro com esse nome: ${_shortTitleList(titles)}.',
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool get _showOnlineAddOption => false;

  void _showAddOptions() {
    final isOnline = _showOnlineAddOption;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final colors = Theme.of(context).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? 'Adicionar online' : 'Adicionar no celular',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (isOnline)
                  const SizedBox.shrink()
                else ...[
                  _AddOptionTile(
                    icon: Icons.folder_open_rounded,
                    title: 'Adicionar pasta',
                    subtitle:
                        'Ler todos os arquivos compatíveis e atualizar quando houver novos.',
                    onTap: () {
                      Navigator.pop(context);
                      _pickLocalFolder();
                    },
                  ),
                  const SizedBox(height: 8),
                  _AddOptionTile(
                    icon: Icons.note_add_outlined,
                    title: 'Adicionar um arquivo',
                    subtitle: 'Escolher PDF, EPUB, TXT ou HQ.',
                    onTap: () {
                      Navigator.pop(context);
                      _pickLocalFiles();
                    },
                  ),
                  const SizedBox(height: 8),
                  _AddOptionTile(
                    icon: Icons.sync_rounded,
                    title: 'Atualizar pastas locais',
                    subtitle: 'Procurar arquivos novos nas pastas adicionadas.',
                    onTap: () {
                      Navigator.pop(context);
                      _syncLocalFolders();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    final libraryState = ref.watch(libraryControllerProvider);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: _buildDrawer(context),
      body: SafeArea(
        child: Stack(
          children: [
            libraryState.when(
              loading: () =>
                  const LoadingView(message: 'Carregando biblioteca...'),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (items) =>
                  _buildContent(context, user?.id, user?.name ?? '', items),
            ),
            if (_isLocalImporting) _buildImportOverlay(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        tooltip: 'Adicionar pasta ou arquivo',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildImportOverlay() {
    final colors = Theme.of(context).colorScheme;
    final progress = _importProgress;
    final percent = progress == null ? null : '${(progress * 100).round()}%';

    if (_isMinimized) {
      return Positioned(
        bottom: 16,
        left: 16,
        right: 16,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _importMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(999),
                        backgroundColor: colors.surfaceContainerHighest,
                        color: colors.primary,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => setState(() => _isMinimized = false),
                icon: const Icon(Icons.open_in_full_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Expandir',
              ),
            ],
          ),
        ),
      );
    }

    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(
          context,
        ).scaffoldBackgroundColor.withValues(alpha: 0.82),
        child: Center(
          child: Container(
            width: 290,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.folder_copy_rounded,
                      color: colors.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _importMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (percent != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        percent,
                        style: TextStyle(
                          color: colors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: colors.surfaceContainerHighest,
                  color: colors.primary,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _isMinimized = true),
                    icon: const Icon(Icons.close_fullscreen_rounded, size: 18),
                    label: const Text('Esperar em segundo plano'),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurfaceVariant,
                      backgroundColor: colors.surfaceContainerHighest,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Você será avisado quando terminar.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    String? userId,
    String userName,
    List<LibraryItem> items,
  ) {
    final colors = Theme.of(context).colorScheme;
    final query = _searchController.text;
    final libraryItems = items.where(_isLibraryItem).toList();
    final visibleItems = libraryItems
        .where((item) => _filter.matches(item))
        .where(
          (item) => itemMatchesSearch(
            item,
            query,
            authorQuery: _authorSearchController.text,
            collectionQuery: _collectionSearchController.text,
          ),
        )
        .toList();
    final localItems = visibleItems
        .where((item) => item.origin == ItemOrigin.local)
        .toList();
    // Apply type filter on top
    final typeFilter = _activeLibraryTypeFilter;
    final visibleItems2 = localItems
        .where((item) => typeFilter.matchesType(item))
        .toList();
    final lastOpenedItem = _lastOpenedItem(userId, libraryItems);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context, userName)),
        SliverToBoxAdapter(child: _buildSearchAndFilters()),
        if (lastOpenedItem != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Continuar lendo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ContinueReadingCard(item: lastOpenedItem),
                ],
              ),
            ),
          ),
        SliverFillRemaining(
          child: _filter == LibraryViewFilter.all
              ? _buildCollections(context, visibleItems2)
              : _buildGrid(context, visibleItems2, isOnline: false),
        ),
      ],
    );
  }

  LibraryItem? _lastOpenedItem(String? userId, List<LibraryItem> items) {
    if (userId == null) return null;
    final itemId = LocalStorageService.getLastOpenedItemId(userId);
    if (itemId == null || itemId.isEmpty) return null;
    return items.cast<LibraryItem?>().firstWhere(
      (item) => item?.id == itemId,
      orElse: () => null,
    );
  }

  bool _isLibraryItem(LibraryItem item) => item.type != ItemType.audio;

  LibraryTypeFilter get _activeLibraryTypeFilter =>
      _typeFilter == LibraryTypeFilter.audio
      ? LibraryTypeFilter.all
      : _typeFilter;

  bool get _hasAdvancedSearch =>
      _authorSearchController.text.trim().isNotEmpty ||
      _collectionSearchController.text.trim().isNotEmpty ||
      _activeLibraryTypeFilter != LibraryTypeFilter.all;

  int get _advancedFilterCount {
    var count = 0;
    if (_authorSearchController.text.trim().isNotEmpty) count++;
    if (_collectionSearchController.text.trim().isNotEmpty) count++;
    if (_activeLibraryTypeFilter != LibraryTypeFilter.all) count++;
    return count;
  }

  Future<void> _showAdvancedSearchSheet() async {
    final authorController = TextEditingController(
      text: _authorSearchController.text,
    );
    final collectionController = TextEditingController(
      text: _collectionSearchController.text,
    );
    var selectedType = _activeLibraryTypeFilter;

    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          final colors = Theme.of(context).colorScheme;

          return StatefulBuilder(
            builder: (context, modalSetState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Busca avancada',
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Fechar',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: authorController,
                        decoration: const InputDecoration(
                          labelText: 'Autor',
                          prefixIcon: Icon(Icons.person_search_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: collectionController,
                        decoration: const InputDecoration(
                          labelText: 'Colecao ou estante',
                          prefixIcon: Icon(Icons.collections_bookmark_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final type in _libraryTypeFilterOptions)
                            ChoiceChip(
                              label: Text(type.label),
                              selected: selectedType == type,
                              onSelected: (_) =>
                                  modalSetState(() => selectedType = type),
                              selectedColor: colors.primary,
                              backgroundColor: colors.surface,
                              labelStyle: TextStyle(
                                color: selectedType == type
                                    ? colors.onPrimary
                                    : colors.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              side: BorderSide(
                                color: selectedType == type
                                    ? colors.primary
                                    : colors.outline,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _authorSearchController.clear();
                                  _collectionSearchController.clear();
                                  _typeFilter = LibraryTypeFilter.all;
                                });
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.filter_alt_off_rounded),
                              label: const Text('Limpar'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _authorSearchController.text =
                                      authorController.text;
                                  _collectionSearchController.text =
                                      collectionController.text;
                                  _typeFilter = selectedType;
                                });
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.check_rounded),
                              label: const Text('Aplicar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      authorController.dispose();
      collectionController.dispose();
    }
  }

  Widget _buildSearchAndFilters() {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por titulo, autor ou estante',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Limpar busca',
                    ),
                  IconButton(
                    onPressed: _showAdvancedSearchSheet,
                    icon: Badge(
                      isLabelVisible: _advancedFilterCount > 0,
                      label: Text('$_advancedFilterCount'),
                      child: Icon(
                        Icons.tune_rounded,
                        color: _hasAdvancedSearch
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    tooltip: 'Busca avancada',
                  ),
                ],
              ),
            ),
          ),
          if (_hasAdvancedSearch) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_authorSearchController.text.trim().isNotEmpty)
                    InputChip(
                      label: Text('Autor: ${_authorSearchController.text}'),
                      onDeleted: _authorSearchController.clear,
                    ),
                  if (_collectionSearchController.text.trim().isNotEmpty)
                    InputChip(
                      label: Text(
                        'Colecao: ${_collectionSearchController.text}',
                      ),
                      onDeleted: _collectionSearchController.clear,
                    ),
                  if (_activeLibraryTypeFilter != LibraryTypeFilter.all)
                    InputChip(
                      label: Text('Tipo: ${_activeLibraryTypeFilter.label}'),
                      onDeleted: () =>
                          setState(() => _typeFilter = LibraryTypeFilter.all),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Status filters row
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: LibraryViewFilter.values.length,
              separatorBuilder: (_, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = LibraryViewFilter.values[index];
                final selected = filter == _filter;
                return ChoiceChip(
                  label: Text(filter.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _filter = filter),
                  labelStyle: TextStyle(
                    color: selected
                        ? colors.onPrimary
                        : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  selectedColor: colors.primary,
                  backgroundColor: colors.surface,
                  side: BorderSide(
                    color: selected ? colors.primary : colors.outline,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String userName) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.menu_rounded,
                    color: colors.onSurface,
                    size: 20,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                AppStrings.appName,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/profile'),
                child: Consumer(
                  builder: (context, ref, child) {
                    final user = ref.watch(authControllerProvider).value;
                    final profileImagePath = user != null
                        ? LocalStorageService.getProfileImage(user.id)
                        : null;

                    if (profileImagePath != null) {
                      return CircleAvatar(
                        radius: 18,
                        backgroundColor: colors.primary,
                        backgroundImage: FileImage(File(profileImagePath)),
                      );
                    }

                    return CircleAvatar(
                      backgroundColor: colors.primary,
                      radius: 18,
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                        style: TextStyle(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Olá, $userName',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sua biblioteca',
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text(
                AppStrings.appName,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            const SizedBox(height: 8),
            _DrawerTile(
              icon: Icons.menu_book_rounded,
              label: 'Biblioteca',
              onTap: () {
                Navigator.pop(context);
                context.go('/library');
              },
            ),
            _DrawerTile(
              icon: Icons.headphones_rounded,
              label: 'Audiobooks',
              onTap: () {
                Navigator.pop(context);
                context.go('/audiobooks');
              },
            ),
            _DrawerTile(
              icon: Icons.sync_rounded,
              label: 'Sincronizar pastas',
              onTap: () {
                Navigator.pop(context);
                _syncLocalFolders();
              },
            ),
            Divider(height: 1, color: colors.outlineVariant),
            _DrawerTile(
              icon: Icons.person_outline_rounded,
              label: 'Perfil',
              onTap: () {
                Navigator.pop(context);
                context.go('/profile');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<LibraryItem> items, {
    required bool isOnline,
  }) {
    if (items.isEmpty) {
      return EmptyState(
        icon: isOnline
            ? Icons.cloud_queue_rounded
            : Icons.phone_android_rounded,
        title: AppStrings.emptyLibrary,
        subtitle: isOnline
            ? 'Adicione arquivos pelo botão +.'
            : 'Toque no botão + para adicionar uma pasta ou um arquivo.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.62,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return BookGridCard(
          item: items[index],
          onTap: () => context.push('/book/${items[index].id}'),
        );
      },
    );
  }

  Widget _buildCollections(BuildContext context, List<LibraryItem> items) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.phone_android_rounded,
        title: AppStrings.emptyLibrary,
        subtitle: 'Toque no botão + para adicionar uma pasta ou um arquivo.',
      );
    }

    final collections = LibraryCollection.fromItems(items);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: collections.length,
      itemBuilder: (context, index) {
        final collection = collections[index];
        return _CollectionCard(
          collection: collection,
          onTap: () => context.push('/collection/${collection.id}'),
        );
      },
    );
  }
}

class _CollectionCard extends StatelessWidget {
  final LibraryCollection collection;
  final VoidCallback onTap;

  const _CollectionCard({required this.collection, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LibraryItemCover(
                        item: collection.coverItem,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                        ),
                        iconSize: 54,
                      ),
                    ),
                    if (collection.newCount > 0)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: AppChip(
                          type: ChipType.newItem,
                          customLabel: collection.newCount > 1
                              ? '${collection.newCount} NOVOS'
                              : 'NOVO',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.name,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${collection.itemCount} arquivo(s)',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AddOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outline),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, color: colors.primary, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: colors.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
