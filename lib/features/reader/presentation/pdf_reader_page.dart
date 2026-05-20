import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../../core/storage/saf_file_resolver.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_item.dart';
import '../../library/domain/reading_progress.dart';
import '../../library/presentation/library_controller.dart';
import '../domain/bookmark.dart';
import 'widgets/bookmarks_sheet.dart';

class PdfReaderPage extends ConsumerStatefulWidget {
  final String itemId;
  const PdfReaderPage({super.key, required this.itemId});

  @override
  ConsumerState<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends ConsumerState<PdfReaderPage> {
  final _uuid = const Uuid();
  PageController? _pageController;
  LibraryItem? _item;
  bool _darkMode = false;
  bool _uiVisible = true;
  bool _horizontalMode = true;
  int _currentPage = 1;
  int _totalPages = 0;
  List<Bookmark> _bookmarks = [];
  DateTime? _sessionStart;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadItem());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    unawaited(_saveProgress(recordSession: true));
    _pageController?.dispose();
    super.dispose();
  }

  void _loadItem() async {
    final items = ref.read(libraryControllerProvider).value;
    if (items == null) return;
    final item = items.cast<LibraryItem?>().firstWhere(
      (e) => e?.id == widget.itemId,
      orElse: () => null,
    );
    if (item == null) return;

    await ref.read(libraryControllerProvider.notifier).markItemOpened(item.id);

    String? resolvedPath;
    if (item.localPath != null) {
      try {
        final resolvedFile = await SafFileResolver.resolveForProcessing(
          item.localPath!,
        );
        resolvedPath = resolvedFile.path;
      } catch (e) {
        debugPrint('Erro ao resolver path SAF: $e');
      }
    }

    if (mounted) {
      setState(() {
        _item = item.copyWith(localPath: resolvedPath ?? item.localPath);
        _currentPage = item.currentPage > 0 ? item.currentPage : 1;
        _pageController = PageController(initialPage: _currentPage - 1);
      });
      _loadBookmarks();
      _sessionStart = DateTime.now();
    }
  }

  void _loadBookmarks() {
    final user = ref.read(authControllerProvider).value;
    final item = _item;
    if (user == null || item == null) return;
    final raw = LocalStorageService.getBookmarks(user.id, item.id);
    setState(() {
      _bookmarks = raw.map((j) => Bookmark.fromJson(j)).toList()
        ..sort((a, b) => (a.page ?? 0).compareTo(b.page ?? 0));
    });
  }

  Future<void> _addBookmark() async {
    final user = ref.read(authControllerProvider).value;
    final item = _item;
    if (user == null || item == null) return;
    final bm = Bookmark.createPdf(
      itemId: item.id,
      userId: user.id,
      page: _currentPage,
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
          if (bm.page != null) {
            _pageController?.jumpToPage(bm.page! - 1);
            setState(() => _currentPage = bm.page!);
          }
        },
        onDelete: _deleteBookmark,
      ),
    );
  }

  Future<void> _saveProgress({bool recordSession = false}) async {
    final item = _item;
    if (item == null) return;
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;

    // Save reading session duration
    if (recordSession && _sessionStart != null) {
      final dur = DateTime.now().difference(_sessionStart!).inSeconds;
      if (dur > 5) {
        await LocalStorageService.saveReadingSession(
          userId: user.id,
          itemId: item.id,
          durationSeconds: dur,
        );
      }
      _sessionStart = null;
    }

    final total = _totalPages > 0 ? _totalPages : 1;
    final percent = (_currentPage / total).clamp(0.0, 1.0);

    final progress = ReadingProgress(
      id: _uuid.v4(),
      userId: user.id,
      itemId: item.id,
      currentPage: _currentPage,
      totalPages: total,
      percent: percent,
      updatedAt: DateTime.now(),
    );

    await ref.read(libraryControllerProvider.notifier).saveProgress(progress);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) await _saveProgress(recordSession: true);
      },
      child: Scaffold(
        backgroundColor: _darkMode ? Colors.black : AppColors.background,
        body: item == null
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : GestureDetector(
                onTap: () => setState(() => _uiVisible = !_uiVisible),
                child: Stack(
                  children: [
                    _buildPdfView(item),
                    if (_uiVisible) ...[
                      _buildTopBar(context, item),
                      _buildBottomBar(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPdfView(LibraryItem item) {
    if (item.localPath != null) {
      return PdfDocumentViewBuilder.file(
        item.localPath!,
        loadingBuilder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        errorBuilder: (_, p1, p2) => _buildError(),
        builder: _buildPageView,
      );
    }

    if (item.remoteUrl != null) {
      return PdfDocumentViewBuilder.uri(
        Uri.parse(item.remoteUrl!),
        loadingBuilder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        errorBuilder: (_, p1, p2) => _buildError(),
        builder: _buildPageView,
      );
    }

    return _buildError();
  }

  Widget _buildError() {
    return const Center(
      child: Text(
        'Arquivo não disponível.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildPageView(BuildContext context, PdfDocument? document) {
    if (document == null) return const SizedBox.shrink();

    if (_totalPages != document.pages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _totalPages = document.pages.length);
      });
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: _horizontalMode ? Axis.horizontal : Axis.vertical,
      itemCount: document.pages.length,
      onPageChanged: (i) {
        if (mounted) {
          setState(() => _currentPage = i + 1);
          _scheduleSaveProgress();
        }
      },
      itemBuilder: (context, index) {
        return InteractiveViewer(
          minScale: 0.8,
          maxScale: 5.0,
          child: Center(
            child: PdfPageView(
              document: document,
              pageNumber: index + 1,
              alignment: Alignment.center,
              backgroundColor: Colors.transparent,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, LibraryItem item) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.5), Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () async {
                    await _saveProgress(recordSession: true);
                    if (!context.mounted) return;
                    context.pop();
                  },
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
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
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.bookmark_border_rounded,
                    color: Colors.white,
                  ),
                  tooltip: 'Favoritar',
                ),
                IconButton(
                  onPressed: () => setState(() => _darkMode = !_darkMode),
                  icon: Icon(
                    _darkMode
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    color: Colors.white,
                  ),
                  tooltip: 'Modo noturno',
                ),
                IconButton(
                  onPressed: _addBookmark,
                  icon: const Icon(
                    Icons.bookmark_add_rounded,
                    color: Colors.white,
                  ),
                  tooltip: 'Adicionar marcador',
                ),
                IconButton(
                  onPressed: _showBookmarks,
                  icon: Stack(
                    children: [
                      const Icon(Icons.bookmarks_rounded, color: Colors.white),
                      if (_bookmarks.isNotEmpty)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  tooltip: 'Ver marcadores (${_bookmarks.length})',
                ),
                IconButton(
                  onPressed: _listenFromCurrentPage,
                  icon: const Icon(
                    Icons.headphones_rounded,
                    color: Colors.white,
                  ),
                  tooltip: 'Ouvir desta pagina',
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _horizontalMode = !_horizontalMode),
                  icon: Icon(
                    _horizontalMode
                        ? Icons.swap_vert_rounded
                        : Icons.swap_horiz_rounded,
                    color: Colors.white,
                  ),
                  tooltip: 'Modo de leitura (Vertical / Horizontal)',
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _totalPages > 0
                        ? '$_currentPage / $_totalPages'
                        : 'p. $_currentPage',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _goToPage,
                  icon: const Icon(Icons.search_rounded, color: Colors.white),
                  tooltip: 'Ir para página',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goToPage() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ir para página'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Número da página'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final page = int.tryParse(ctrl.text);
              if (page != null && page > 0 && page <= _totalPages) {
                _pageController?.jumpToPage(page - 1);
                setState(() => _currentPage = page);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Ir'),
          ),
        ],
      ),
    );
  }

  void _scheduleSaveProgress() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 700), () {
      unawaited(_saveProgress());
    });
  }

  Future<void> _listenFromCurrentPage() async {
    await _saveProgress(recordSession: true);
    if (!mounted) return;
    context.push('/listen/${widget.itemId}');
  }
}
