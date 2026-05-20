import 'dart:async';
import 'dart:math' as math;

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
import '../domain/book_text_extractor.dart';
import '../domain/bookmark.dart';
import '../domain/translation_service.dart';
import '../domain/tts_speaker_service.dart';
import 'widgets/bookmarks_sheet.dart';

class PdfReaderPage extends ConsumerStatefulWidget {
  final String itemId;
  const PdfReaderPage({super.key, required this.itemId});

  @override
  ConsumerState<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends ConsumerState<PdfReaderPage> {
  final _uuid = const Uuid();
  final _translator = TranslationService();
  final _transformControllers = <int, TransformationController>{};
  PageController? _pageController;
  PdfDocument? _activePdfDocument;
  LibraryItem? _item;
  bool _darkMode = false;
  bool _uiVisible = true;
  bool _horizontalMode = true;
  int _currentPage = 1;
  int _totalPages = 0;
  List<Bookmark> _bookmarks = [];
  DateTime? _sessionStart;
  Timer? _saveDebounce;
  bool _isTranslating = false;
  TranslationLang _pdfTranslationLang = TranslationLang.english;
  _PdfPageTranslation? _translatedPdfPage;
  String? _translationError;
  String _pdfTranslationStatus = 'Preparando...';
  int _pdfTranslationRequestId = 0;
  double _pdfScale = 1.0;
  TapDownDetails? _lastPdfDoubleTapDetails;
  bool _isLoadingPdf = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadItem());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    unawaited(_saveProgress(recordSession: true));
    for (final controller in _transformControllers.values) {
      controller.dispose();
    }
    _transformControllers.clear();
    _pageController?.dispose();
    _activePdfDocument?.dispose();
    TtsSpeakerService.stop();
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
      _openPdfDocument();
    }
  }

  Future<void> _openPdfDocument() async {
    final item = _item;
    if (item == null) return;
    
    try {
      PdfDocument? doc;
      if (item.localPath != null) {
        doc = await PdfDocument.openFile(item.localPath!);
      } else if (item.remoteUrl != null) {
        doc = await PdfDocument.openUri(Uri.parse(item.remoteUrl!));
      }
      
      if (mounted) {
        setState(() {
          _activePdfDocument = doc;
          _totalPages = doc?.pages.length ?? 0;
          _isLoadingPdf = false;
        });
      } else {
        doc?.dispose();
      }
    } catch (e) {
      debugPrint('Erro ao abrir PDF: $e');
      if (mounted) {
        setState(() => _isLoadingPdf = false);
      }
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
            setState(() {
              _currentPage = bm.page!;
              _clearPdfTranslationState();
            });
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
            : Stack(
                children: [
                  _buildPdfView(item),
                  if (_isTranslating || _translationError != null)
                    _buildPdfTranslationStatusPanel(),
                  if (_uiVisible) ...[
                    _buildTopBar(context, item),
                    _buildBottomBar(),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildPdfView(LibraryItem item) {
    if (_isLoadingPdf) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_activePdfDocument == null) {
      return _buildError();
    }

    return _buildPageView(context, _activePdfDocument!);
  }

  Widget _buildError() {
    return const Center(
      child: Text(
        'Arquivo não disponível.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildPageView(BuildContext context, PdfDocument document) {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: _horizontalMode ? Axis.horizontal : Axis.vertical,
      physics: _pdfScale > 1.05
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      itemCount: document.pages.length,
      onPageChanged: (i) {
        if (mounted) {
          final prevIndex = _currentPage - 1;
          if (prevIndex >= 0 && prevIndex != i) {
            _resetPdfZoomOfIndex(prevIndex);
          }
          setState(() {
            _currentPage = i + 1;
            _clearPdfTranslationState();
            final controller = _transformControllers[i];
            _pdfScale = controller?.value.getMaxScaleOnAxis() ?? 1.0;
          });
          _scheduleSaveProgress();
        }
      },
      itemBuilder: (context, index) {
        final page = document.pages[index];
        final controller = _getOrCreateTransformController(index);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => setState(() => _uiVisible = !_uiVisible),
          onDoubleTapDown: (details) => _lastPdfDoubleTapDetails = details,
          onDoubleTap: _togglePdfDoubleTapZoom,
          child: InteractiveViewer(
            transformationController: controller,
            minScale: 0.8,
            maxScale: 5.0,
            panEnabled: _pdfScale > 1.05,
            scaleEnabled: true,
            boundaryMargin: _pdfScale > 1.05 ? const EdgeInsets.all(96) : EdgeInsets.zero,
            clipBehavior: Clip.none,
            onInteractionUpdate: (details) {
              final nextScale = controller.value.getMaxScaleOnAxis();
              final isZoomed = nextScale > 1.05;
              final wasZoomed = _pdfScale > 1.05;
              if (isZoomed != wasZoomed) {
                setState(() {
                  _pdfScale = isZoomed ? nextScale : 1.0;
                });
              }
            },
            onInteractionEnd: (details) {
              final nextScale = controller.value.getMaxScaleOnAxis();
              final isZoomed = nextScale > 1.05;
              setState(() {
                _pdfScale = isZoomed ? nextScale : 1.0;
              });
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pageSize = _fitPdfPageSize(
                  page,
                  Size(constraints.maxWidth, constraints.maxHeight),
                );

                return Center(
                  child: SizedBox(
                    width: pageSize.width,
                    height: pageSize.height,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: PdfPageView(
                            key: ValueKey('pdf_page_${index + 1}'),
                            document: document,
                            pageNumber: index + 1,
                            alignment: Alignment.center,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                        if (_translatedPdfPage?.pageNumber == page.pageNumber)
                          Positioned.fill(
                            child: _PdfTranslationLayer(
                              page: page,
                              pageSize: pageSize,
                              translation: _translatedPdfPage!,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
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
                        const Icon(
                          Icons.bookmarks_rounded,
                          color: Colors.white,
                        ),
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
                    onPressed: _translatedPdfPage != null
                        ? () => setState(_clearPdfTranslationState)
                        : _openPdfTranslationPicker,
                    icon: Icon(
                      _translatedPdfPage != null
                          ? Icons.translate_outlined
                          : Icons.translate_rounded,
                      color: Colors.white,
                    ),
                    tooltip: _translatedPdfPage != null
                        ? 'Fechar traducao'
                        : 'Traduzir pagina',
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
                  IconButton(
                    onPressed: _zoomOutPdf,
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Diminuir zoom',
                  ),
                  IconButton(
                    onPressed: _zoomInPdf,
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Aumentar zoom',
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
      ),
    );
  }

  void _clearPdfTranslationState() {
    _pdfTranslationRequestId++;
    _isTranslating = false;
    _translatedPdfPage = null;
    _translationError = null;
    _pdfTranslationStatus = 'Preparando...';
  }

  void _openPdfTranslationPicker() {
    if (_isTranslating) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Traduzir pagina do PDF',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Escolha o idioma original. O texto sera traduzido para PT-BR.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ...TranslationLang.values.map((lang) {
                  final isSelected = lang == _pdfTranslationLang;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white24 : Colors.white10,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.translate_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      lang.label,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.lightBlueAccent,
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(_translateCurrentPdfPage(lang));
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _translateCurrentPdfPage(TranslationLang sourceLang) async {
    final item = _item;
    if (item == null) return;

    final page = _currentPage;
    final requestId = ++_pdfTranslationRequestId;

    setState(() {
      _pdfTranslationLang = sourceLang;
      _isTranslating = true;
      _uiVisible = false;
      _translatedPdfPage = null;
      _translationError = null;
      _pdfTranslationStatus = 'Extraindo texto da pagina...';
    });

    try {
      final document = _activePdfDocument;
      if (document == null || page < 1 || page > document.pages.length) {
        throw const BookTextExtractionException(
          'Aguarde o PDF terminar de carregar para traduzir a pagina.',
        );
      }

      final pdfPage = document.pages[page - 1];
      final pageText = await pdfPage.loadStructuredText();
      if (!mounted || requestId != _pdfTranslationRequestId) return;

      final lineBlocks = _buildPdfTranslationLineBlocks(pdfPage, pageText);

      if (lineBlocks.isEmpty) {
        throw const BookTextExtractionException(
          'Nao encontrei texto selecionavel nesta pagina. Se for PDF escaneado, precisa OCR.',
        );
      }

      final translated = await _translator.translateBatch(
        lineBlocks.map((block) => block.originalText).toList(growable: false),
        sourceLang: sourceLang,
        onProgress: (current, total) {
          if (!mounted || requestId != _pdfTranslationRequestId) return;
          setState(() {
            _pdfTranslationStatus = 'Traduzindo $current/$total...';
          });
        },
      );

      if (!mounted || requestId != _pdfTranslationRequestId) return;

      final blocks = <_PdfTranslationBlock>[];
      for (var i = 0; i < lineBlocks.length; i++) {
        final translatedText = i < translated.length
            ? translated[i].trim()
            : '';
        if (translatedText.isEmpty) continue;
        blocks.add(lineBlocks[i].copyWith(translatedText: translatedText));
      }

      setState(() {
        _isTranslating = false;
        if (blocks.isEmpty) {
          _translationError = 'Nao consegui traduzir o texto desta pagina.';
        } else {
          _translatedPdfPage = _PdfPageTranslation(
            pageNumber: page,
            blocks: blocks,
          );
        }
      });
    } on BookTextExtractionException catch (error) {
      if (!mounted || requestId != _pdfTranslationRequestId) return;
      setState(() {
        _isTranslating = false;
        _translationError = error.message;
      });
    } catch (error, stackTrace) {
      debugPrint('Erro ao traduzir PDF: $error\n$stackTrace');
      if (!mounted || requestId != _pdfTranslationRequestId) return;
      setState(() {
        _isTranslating = false;
        _translationError = 'Nao foi possivel traduzir esta pagina agora.';
      });
    }
  }

  Widget _buildPdfTranslationStatusPanel() {
    final bottom = _uiVisible ? 112.0 : 24.0;
    final error = _translationError;
    final title = _isTranslating
        ? _pdfTranslationStatus
        : 'Traducao indisponivel';

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: SafeArea(
        top: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 18,
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
                      const Icon(
                        Icons.translate_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(_clearPdfTranslationState),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                        tooltip: 'Fechar traducao',
                      ),
                    ],
                  ),
                  if (_isTranslating) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(
                      color: AppColors.primary,
                      backgroundColor: Colors.white24,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'A traducao fica aberta ate trocar de pagina ou fechar.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ] else if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Size _fitPdfPageSize(PdfPage page, Size availableSize) {
    final pageSize = page.size;
    if (pageSize.width <= 0 ||
        pageSize.height <= 0 ||
        availableSize.width <= 0 ||
        availableSize.height <= 0) {
      return pageSize;
    }

    final scale = math.min(
      availableSize.width / pageSize.width,
      availableSize.height / pageSize.height,
    );
    return Size(pageSize.width * scale, pageSize.height * scale);
  }

  List<_PdfTranslationBlock> _buildPdfTranslationLineBlocks(
    PdfPage page,
    PdfPageText pageText,
  ) {
    final text = pageText.fullText;
    if (text.trim().isEmpty || pageText.charRects.isEmpty) return const [];

    final blocks = <_PdfTranslationBlock>[];

    void addLine(int rawStart, int rawEnd) {
      var start = rawStart;
      var end = rawEnd;
      while (start < end && text[start].trim().isEmpty) {
        start++;
      }
      while (end > start && text[end - 1].trim().isEmpty) {
        end--;
      }
      if (end <= start || start >= pageText.charRects.length) return;

      end = math.min(end, pageText.charRects.length);
      final original = text
          .substring(start, end)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (original.length < 2) return;

      final pdfBounds = pageText.charRects.boundingRect(start: start, end: end);
      if (pdfBounds.width <= 1 || pdfBounds.height <= 1) return;

      final pageBounds = pdfBounds.toRect(page: page);
      if (pageBounds.width <= 2 || pageBounds.height <= 2) return;

      blocks.add(
        _PdfTranslationBlock(
          originalText: original,
          translatedText: '',
          pageBounds: pageBounds,
          fontSize: _estimatePdfLineFontSize(pageText, start, end),
        ),
      );
    }

    var lineStart = 0;
    for (final match in RegExp(r'\r?\n').allMatches(text)) {
      addLine(lineStart, match.start);
      lineStart = match.end;
    }
    addLine(lineStart, text.length);

    return blocks;
  }

  double _estimatePdfLineFontSize(PdfPageText pageText, int start, int end) {
    final heights =
        pageText.charRects
            .skip(start)
            .take(end - start)
            .where((rect) => rect.isNotEmpty)
            .map((rect) => rect.height)
            .where((height) => height > 0)
            .toList()
          ..sort();

    if (heights.isEmpty) return 10;
    return heights[heights.length ~/ 2].clamp(4.0, 28.0);
  }

  TransformationController _getOrCreateTransformController(int index) {
    return _transformControllers.putIfAbsent(index, () => TransformationController());
  }

  TransformationController get _currentPdfTransformController {
    final index = _currentPage - 1;
    return _getOrCreateTransformController(index);
  }

  void _resetPdfZoom() {
    _currentPdfTransformController.value = Matrix4.identity();
    if (mounted && (_pdfScale - 1.0).abs() >= 0.01) {
      setState(() => _pdfScale = 1.0);
    }
  }

  void _resetPdfZoomOfIndex(int index) {
    final controller = _transformControllers[index];
    if (controller != null) {
      controller.value = Matrix4.identity();
    }
  }

  void _zoomInPdf() => _setPdfZoom(_pdfScale * 1.35);

  void _zoomOutPdf() {
    final next = _pdfScale / 1.35;
    if (next <= 1.05) {
      _resetPdfZoom();
    } else {
      _setPdfZoom(next);
    }
  }

  void _togglePdfDoubleTapZoom() {
    if (_pdfScale > 1.05) {
      _resetPdfZoom();
      return;
    }

    _setPdfZoom(2.4, focalPoint: _lastPdfDoubleTapDetails?.localPosition);
  }

  void _setPdfZoom(double targetScale, {Offset? focalPoint}) {
    final target = targetScale.clamp(0.8, 5.0);
    if (target <= 1.05) {
      _resetPdfZoom();
      return;
    }

    final viewport = MediaQuery.sizeOf(context);
    final focal = focalPoint ?? Offset(viewport.width / 2, viewport.height / 2);
    final controller = _currentPdfTransformController;
    final scenePoint = controller.toScene(focal);
    setState(() {
      controller.value = Matrix4.identity()
        ..setEntry(0, 0, target)
        ..setEntry(1, 1, target)
        ..setTranslationRaw(
          focal.dx - scenePoint.dx * target,
          focal.dy - scenePoint.dy * target,
          0,
        );
      _pdfScale = target;
    });
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
                setState(() {
                  _currentPage = page;
                  _clearPdfTranslationState();
                });
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

class _PdfPageTranslation {
  final int pageNumber;
  final List<_PdfTranslationBlock> blocks;

  const _PdfPageTranslation({required this.pageNumber, required this.blocks});
}

class _PdfTranslationBlock {
  final String originalText;
  final String translatedText;
  final Rect pageBounds;
  final double fontSize;

  const _PdfTranslationBlock({
    required this.originalText,
    required this.translatedText,
    required this.pageBounds,
    required this.fontSize,
  });

  _PdfTranslationBlock copyWith({required String translatedText}) {
    return _PdfTranslationBlock(
      originalText: originalText,
      translatedText: translatedText,
      pageBounds: pageBounds,
      fontSize: fontSize,
    );
  }
}

class _PdfTranslationLayer extends StatelessWidget {
  final PdfPage page;
  final Size pageSize;
  final _PdfPageTranslation translation;

  const _PdfTranslationLayer({
    required this.page,
    required this.pageSize,
    required this.translation,
  });

  @override
  Widget build(BuildContext context) {
    final scaleX = pageSize.width / page.width;
    final scaleY = pageSize.height / page.height;

    return Stack(
      children: [
        for (final block in translation.blocks)
          _buildTranslatedBlock(block, scaleX, scaleY),
      ],
    );
  }

  Widget _buildTranslatedBlock(
    _PdfTranslationBlock block,
    double scaleX,
    double scaleY,
  ) {
    final rect = Rect.fromLTRB(
      block.pageBounds.left * scaleX,
      block.pageBounds.top * scaleY,
      block.pageBounds.right * scaleX,
      block.pageBounds.bottom * scaleY,
    ).inflate(math.max(0.6, block.fontSize * scaleY * 0.10));

    if (rect.width < 4 || rect.height < 4) return const SizedBox.shrink();

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final text = block.translatedText;
          TtsSpeakerService.speak(text, language: 'pt-BR');
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(1.5),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: math.max(0.6, block.fontSize * scaleX * 0.08),
            ),
            child: _PdfAutoFitText(
              text: _displayPdfTranslationText(block),
              maxFontSize: (block.fontSize * scaleY).clamp(3.5, 26.0),
              minFontSize: 3.0,
            ),
          ),
        ),
      ),
    );
  }

  String _displayPdfTranslationText(_PdfTranslationBlock block) {
    final translated = block.translatedText.trim();
    if (!_originalLooksUppercase(block.originalText)) return translated;
    return translated.toUpperCase();
  }

  bool _originalLooksUppercase(String value) {
    final letters = RegExp(r'[A-Za-z]').allMatches(value).toList();
    if (letters.length < 4) return false;

    final uppercase = letters
        .where((match) => match.group(0) == match.group(0)!.toUpperCase())
        .length;
    return uppercase / letters.length >= 0.70;
  }
}

class _PdfAutoFitText extends StatelessWidget {
  final String text;
  final double maxFontSize;
  final double minFontSize;

  const _PdfAutoFitText({
    required this.text,
    required this.maxFontSize,
    required this.minFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayText = _withBreakOpportunities(text);
        final fittedFontSize = _fitFontSize(
          text: displayText,
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          textDirection: Directionality.of(context),
        );

        return Text(
          displayText,
          maxLines: null,
          softWrap: true,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: Colors.black,
            fontSize: fittedFontSize,
            fontWeight: FontWeight.w600,
            height: 1.0,
            letterSpacing: 0,
          ),
        );
      },
    );
  }

  double _fitFontSize({
    required String text,
    required double maxWidth,
    required double maxHeight,
    required TextDirection textDirection,
  }) {
    if (maxWidth <= 0 || maxHeight <= 0) return minFontSize;

    var low = minFontSize;
    var high = maxFontSize;

    for (var i = 0; i < 12; i++) {
      final mid = (low + high) / 2;
      if (_fits(
        text: text,
        fontSize: mid,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        textDirection: textDirection,
      )) {
        low = mid;
      } else {
        high = mid;
      }
    }

    return low;
  }

  bool _fits({
    required String text,
    required double fontSize,
    required double maxWidth,
    required double maxHeight,
    required TextDirection textDirection,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          height: 1.0,
          letterSpacing: 0,
        ),
      ),
      textDirection: textDirection,
      maxLines: null,
    )..layout(maxWidth: maxWidth);

    return painter.width <= maxWidth + 0.1 && painter.height <= maxHeight + 0.1;
  }

  String _withBreakOpportunities(String value) {
    return value.splitMapJoin(
      RegExp(r'\S{14,}'),
      onMatch: (match) => _splitLongToken(match.group(0)!),
      onNonMatch: (text) => text,
    );
  }

  String _splitLongToken(String value) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      buffer.write(value[i]);
      if ((i + 1) % 8 == 0 && i != value.length - 1) {
        buffer.write('\u200B');
      }
    }
    return buffer.toString();
  }
}
