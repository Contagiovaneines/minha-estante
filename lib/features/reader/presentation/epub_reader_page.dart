import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_epub_viewer/flutter_epub_viewer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../../core/storage/saf_file_resolver.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_item.dart';
import '../../library/domain/reading_progress.dart';
import '../../library/presentation/library_controller.dart';
import '../domain/bookmark.dart';
import '../domain/ebook_format_support.dart';
import 'widgets/bookmarks_sheet.dart';

class EpubReaderPage extends ConsumerStatefulWidget {
  final String itemId;

  const EpubReaderPage({super.key, required this.itemId});

  @override
  ConsumerState<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends ConsumerState<EpubReaderPage> {
  final _uuid = const Uuid();
  final _epubController = EpubController();

  LibraryItem? _item;
  EpubSource? _source;
  EpubLocation? _lastLocation;
  Timer? _saveDebounce;
  String? _initialCfi;
  double _initialProgress = 0;
  double _progress = 0;
  double _fontSize = 17;
  bool _isLoading = true;
  bool _uiVisible = true;
  bool _darkMode = false;
  bool _isLoaded = false;
  bool _fallbackProgressApplied = false;
  String? _errorMessage;
  List<Bookmark> _bookmarks = [];
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadItem());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    // Record reading session before dispose
    if (_sessionStart != null && _item != null) {
      final user = ref.read(authControllerProvider).value;
      final dur = DateTime.now().difference(_sessionStart!).inSeconds;
      if (user != null && dur > 5) {
        LocalStorageService.saveReadingSession(
          userId: user.id,
          itemId: _item!.id,
          durationSeconds: dur,
        );
      }
      _sessionStart = null;
    }
    unawaited(_saveProgress());
    super.dispose();
  }

  Future<void> _loadItem() async {
    final items = ref.read(libraryControllerProvider).value;
    if (items == null) return;

    final item = items.cast<LibraryItem?>().firstWhere(
      (entry) => entry?.id == widget.itemId,
      orElse: () => null,
    );
    if (item == null) {
      if (mounted) setState(() => _errorMessage = 'Arquivo não encontrado.');
      return;
    }

    if (!EbookFormatSupport.canReadInternally(item)) {
      if (mounted) {
        setState(() {
          _item = item;
          _errorMessage =
              'Este formato ainda não possui leitor interno nesta versão. '
              'Converta para EPUB para ler no app.';
          _isLoading = false;
        });
      }
      return;
    }

    await ref.read(libraryControllerProvider.notifier).markItemOpened(item.id);
    final progress = await ref
        .read(libraryControllerProvider.notifier)
        .getProgress(item.id);

    try {
      final source = await _sourceFor(item);
      if (!mounted) return;
      setState(() {
        _item = item;
        _source = source;
        _initialCfi = progress?.epubCfi;
        _initialProgress = progress?.percent ?? item.progress;
        _progress = _initialProgress;
        _isLoading = true;
        _errorMessage = null;
      });
      _loadBookmarks();
      _sessionStart = DateTime.now();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _item = item;
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<EpubSource> _sourceFor(LibraryItem item) async {
    final localPath = item.localPath;
    if (localPath != null && localPath.trim().isNotEmpty) {
      final file = await SafFileResolver.resolveForProcessing(localPath);
      return EpubSource.fromFile(file);
    }

    final remoteUrl = item.remoteUrl;
    if (remoteUrl != null && remoteUrl.trim().isNotEmpty) {
      return EpubSource.fromUrl(
        remoteUrl,
        headers: const {'Accept': 'application/epub+zip,*/*'},
      );
    }

    throw Exception('Arquivo EPUB não disponível.');
  }

  Future<void> _saveProgress() async {
    final item = _item;
    final location = _lastLocation;
    if (item == null || location == null) return;

    final user = ref.read(authControllerProvider).value;
    if (user == null) return;

    final percent = location.progress.isFinite
        ? location.progress.clamp(0.0, 1.0).toDouble()
        : _progress.clamp(0.0, 1.0).toDouble();

    final progress = ReadingProgress(
      id: _uuid.v4(),
      userId: user.id,
      itemId: item.id,
      currentPage: 0,
      totalPages: 0,
      percent: percent,
      epubCfi: location.startCfi,
      epubEndCfi: location.endCfi,
      epubStartXpath: location.startXpath,
      epubEndXpath: location.endXpath,
      updatedAt: DateTime.now(),
    );

    await ref.read(libraryControllerProvider.notifier).saveProgress(progress);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(_saveProgress());
    });
  }

  void _loadBookmarks() {
    final user = ref.read(authControllerProvider).value;
    final item = _item;
    if (user == null || item == null) return;
    final raw = LocalStorageService.getBookmarks(user.id, item.id);
    setState(() {
      _bookmarks = raw.map((j) => Bookmark.fromJson(j)).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
  }

  Future<void> _addBookmark() async {
    final user = ref.read(authControllerProvider).value;
    final item = _item;
    if (user == null || item == null) return;
    final cfi = _lastLocation?.startCfi ?? '';
    if (cfi.isEmpty) return;
    final pct = (_progress * 100).toStringAsFixed(0);
    final bm = Bookmark.createEpub(
      itemId: item.id,
      userId: user.id,
      cfi: cfi,
      label: 'Trecho em $pct%',
    );
    await LocalStorageService.saveBookmark(user.id, bm.toJson());
    _loadBookmarks();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marcador adicionado!'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteBookmark(Bookmark bm) async {
    final user = ref.read(authControllerProvider).value;
    final item = _item;
    if (user == null || item == null) return;
    await LocalStorageService.deleteBookmark(user.id, item.id, bm.id);
    _loadBookmarks();
  }

  void _showBookmarks() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BookmarksSheet(
        bookmarks: _bookmarks,
        onTap: (bm) {
          if (bm.cfi != null && bm.cfi!.isNotEmpty && _isLoaded) {
            _epubController.display(cfi: bm.cfi!);
          }
        },
        onDelete: _deleteBookmark,
      ),
    );
  }

  void _onRelocated(EpubLocation location) {
    if (!mounted) return;
    setState(() {
      _lastLocation = location;
      _progress = location.progress.clamp(0.0, 1.0).toDouble();
    });
    _scheduleSave();
  }

  void _onLocationLoaded() {
    if (_fallbackProgressApplied) return;
    if ((_initialCfi ?? '').isNotEmpty || _initialProgress <= 0) return;
    _fallbackProgressApplied = true;
    try {
      _epubController.toProgressPercentage(
        _initialProgress.clamp(0.0, 1.0).toDouble(),
      );
    } catch (_) {
      // O CFI é o caminho principal; porcentagem é apenas fallback.
    }
  }

  Future<void> _close() async {
    _saveDebounce?.cancel();
    await _saveProgress();
    if (mounted) context.pop();
  }

  void _toggleTheme() {
    setState(() => _darkMode = !_darkMode);
    if (!_isLoaded) return;
    unawaited(
      _epubController.updateTheme(
        theme: _darkMode ? EpubTheme.dark() : EpubTheme.light(),
      ),
    );
  }

  void _changeFontSize(double delta) {
    final nextSize = (_fontSize + delta).clamp(13.0, 24.0).toDouble();
    if (nextSize == _fontSize) return;
    setState(() => _fontSize = nextSize);
    if (!_isLoaded) return;
    unawaited(_epubController.setFontSize(fontSize: _fontSize));
  }

  void _nextPage() {
    if (!_isLoaded) return;
    _epubController.next();
  }

  void _previousPage() {
    if (!_isLoaded) return;
    _epubController.prev();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final source = _source;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) await _saveProgress();
      },
      child: Scaffold(
        backgroundColor: _darkMode ? Colors.black : AppColors.background,
        body: item == null
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _errorMessage != null
            ? _buildError(item)
            : source == null
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : Stack(
                children: [
                  Positioned.fill(child: _buildReader(source)),
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  if (_uiVisible) _buildTopBar(item),
                  if (_uiVisible) _buildBottomBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildReader(EpubSource source) {
    return SafeArea(
      child: EpubViewer(
        epubSource: source,
        epubController: _epubController,
        initialCfi: (_initialCfi?.trim().isNotEmpty ?? false)
            ? _initialCfi
            : null,
        displaySettings: EpubDisplaySettings(
          fontSize: _fontSize.round(),
          flow: EpubFlow.paginated,
          spread: EpubSpread.auto,
          snap: true,
          useSnapAnimationAndroid: false,
          theme: _darkMode ? EpubTheme.dark() : EpubTheme.light(),
        ),
        onEpubLoaded: () {
          if (!mounted) return;
          setState(() {
            _isLoaded = true;
            _isLoading = false;
          });
        },
        onLocationLoaded: _onLocationLoaded,
        onRelocated: _onRelocated,
        onTouchUp: (x, y) {
          if (y < 0.15 || (x > 0.36 && x < 0.64)) {
            setState(() => _uiVisible = !_uiVisible);
            return;
          }
          if (x >= 0.64) {
            _nextPage();
          } else if (x <= 0.36) {
            _previousPage();
          }
        },
      ),
    );
  }

  Widget _buildTopBar(LibraryItem item) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: (_darkMode ? Colors.black : AppColors.surface).withValues(
          alpha: 0.92,
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: _close,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: _darkMode ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                Expanded(
                  child: Text(
                    item.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _darkMode ? Colors.white : AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _toggleTheme,
                  tooltip: _darkMode ? 'Tema claro' : 'Tema escuro',
                  icon: Icon(
                    _darkMode
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    color: _darkMode ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final textColor = _darkMode ? Colors.white : AppColors.textPrimary;
    final mutedColor = _darkMode ? Colors.white70 : AppColors.textSecondary;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: (_darkMode ? Colors.black : AppColors.surface).withValues(
          alpha: 0.94,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                IconButton(
                  onPressed: _previousPage,
                  tooltip: 'Página anterior',
                  icon: Icon(Icons.chevron_left_rounded, color: textColor),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: _progress.clamp(0.0, 1.0).toDouble(),
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(999),
                        backgroundColor: mutedColor.withValues(alpha: 0.2),
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _nextPage,
                  tooltip: 'Próxima página',
                  icon: Icon(Icons.chevron_right_rounded, color: textColor),
                ),
                IconButton(
                  onPressed: () => _changeFontSize(-1),
                  tooltip: 'Diminuir fonte',
                  icon: Icon(Icons.text_decrease_rounded, color: textColor),
                ),
                IconButton(
                  onPressed: () => _changeFontSize(1),
                  tooltip: 'Aumentar fonte',
                  icon: Icon(Icons.text_increase_rounded, color: textColor),
                ),
                IconButton(
                  onPressed: _addBookmark,
                  tooltip: 'Adicionar marcador',
                  icon: Icon(Icons.bookmark_add_rounded, color: textColor),
                ),
                IconButton(
                  onPressed: _showBookmarks,
                  tooltip: 'Ver marcadores',
                  icon: Stack(
                    children: [
                      Icon(Icons.bookmarks_rounded, color: textColor),
                      if (_bookmarks.isNotEmpty)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(LibraryItem item) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => context.pop(),
                ),
                Expanded(
                  child: Text(
                    item.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
