import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/cbz_reader_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../library/domain/library_item.dart';
import '../../library/presentation/library_controller.dart';
import 'cbr_conversion_page.dart';
import '../../../core/storage/saf_file_resolver.dart';
import '../domain/translation_service.dart';
import 'widgets/translation_overlay.dart';

class HqReaderPage extends ConsumerWidget {
  final String itemId;

  const HqReaderPage({super.key, required this.itemId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryControllerProvider);

    return libraryState.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.comicAccent),
        ),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Erro: $error')),
      ),
      data: (items) {
        final item = items.cast<LibraryItem?>().firstWhere(
          (e) => e?.id == itemId,
          orElse: () => null,
        );

        if (item == null || item.localPath == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Arquivo não encontrado.')),
          );
        }

        return _HqReaderView(item: item);
      },
    );
  }
}

class HqReaderDirectPage extends StatelessWidget {
  final LibraryItem item;

  const HqReaderDirectPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.localPath == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Arquivo não encontrado.')),
      );
    }
    return _HqReaderView(item: item);
  }
}

class _HqReaderView extends ConsumerStatefulWidget {
  final LibraryItem item;
  const _HqReaderView({required this.item});

  @override
  ConsumerState<_HqReaderView> createState() => _HqReaderViewState();
}

class _HqReaderViewState extends ConsumerState<_HqReaderView> {
  late final PageController _pageController;
  List<File>? _pages;
  String? _error;
  bool _showBars = true;
  int _currentPage = 0;
  final _cbzService = CbzReaderService();

  bool _showTranslation = false;
  TranslationLang _translationLang = TranslationLang.japanese;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
      ref
          .read(libraryControllerProvider.notifier)
          .markItemOpened(widget.item.id);
    });
    _extractPages();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _cbzService.cleanup(widget.item.id);
    super.dispose();
  }

  Future<void> _extractPages() async {
    try {
      final path = widget.item.localPath!;
      final ext = path.toLowerCase();

      if (ext.endsWith('.cbr') ||
          ext.endsWith('.cb7') ||
          ext.endsWith('.rar')) {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => CbrConversionPage(item: widget.item),
              ),
            );
          });
        }
        return;
      }

      if (!ext.endsWith('.cbz') && !ext.endsWith('.zip')) {
        throw Exception('Formato não suportado.');
      }

      final resolvedFile = await SafFileResolver.resolveForProcessing(path);
      final pages = await _cbzService.extractCbz(
        resolvedFile.path,
        widget.item.id,
      );

      if (mounted) {
        setState(() => _pages = pages);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  void _toggleBars() => setState(() => _showBars = !_showBars);

  void _goTo(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _openTranslationPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        if (!mounted) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Traduzir de qual idioma?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Texto detectado será traduzido para Português',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ...TranslationLang.values.map((lang) {
                  final isSelected = lang == _translationLang;
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
                      setState(() {
                        _translationLang = lang;
                        _showTranslation = true;
                      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showBars && !_showTranslation
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.75),
              foregroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                widget.item.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
              actions: [
                if (_pages != null)
                  IconButton(
                    onPressed: _showTranslation
                        ? () => setState(() => _showTranslation = false)
                        : _openTranslationPicker,
                    icon: Icon(
                      _showTranslation
                          ? Icons.translate_rounded
                          : Icons.translate_outlined,
                      color: _showTranslation
                          ? Colors.lightBlueAccent
                          : Colors.white,
                    ),
                    tooltip: _showTranslation
                        ? 'Fechar tradução'
                        : 'Traduzir página',
                  ),
                if (_pages != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: Text(
                        '${_currentPage + 1} / ${_pages!.length}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : null,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) return _buildError();
    if (_pages == null) return _buildLoading();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _showTranslation ? null : _toggleBars,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _pages!.length,
              onPageChanged: (i) => setState(() {
                _currentPage = i;
                _showTranslation = false;
              }),
              itemBuilder: (context, index) =>
                  _buildPageImage(_pages![index], index),
            ),
          ),
        ),
        if (_showTranslation && _pages != null)
          Positioned.fill(
            child: TranslationOverlay(
              imageFile: _pages![_currentPage],
              sourceLang: _translationLang,
              onClose: () => setState(() => _showTranslation = false),
              onLangChanged: (lang) => setState(() => _translationLang = lang),
            ),
          ),
        if (_showBars && !_showTranslation)
          Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomBar()),
      ],
    );
  }

  Widget _buildPageImage(File file, int index) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final cacheWidth = (maxWidth * dpr * 2).round().clamp(1, 4096);

        return InteractiveViewer(
          minScale: 0.8,
          maxScale: 5.0,
          child: Center(
            child: Image.file(
              file,
              key: ValueKey(file.path),
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              fit: BoxFit.contain,
              cacheWidth: cacheWidth,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) return child;
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.comicAccent,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) =>
                  _buildPageError(index),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageError(int index) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_rounded,
              color: Colors.white54,
              size: 56,
            ),
            const SizedBox(height: 12),
            Text(
              'Não foi possível renderizar a página ${index + 1}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.comicAccent),
          SizedBox(height: 16),
          Text(
            'Extraindo páginas...',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 52,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              label: const Text(
                'Voltar',
                style: TextStyle(color: Colors.white),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final pages = _pages!;
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_rounded,
                color: Colors.white70,
                size: 20,
              ),
              onPressed: _currentPage > 0
                  ? () => _goTo(_currentPage - 1)
                  : null,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.comicAccent,
                  thumbColor: AppColors.comicAccent,
                  inactiveTrackColor: Colors.white24,
                  overlayColor: AppColors.comicAccent.withValues(alpha: 0.2),
                  trackHeight: 3,
                ),
                child: Slider(
                  min: 0,
                  max: (pages.length - 1).toDouble(),
                  value: _currentPage.toDouble(),
                  onChanged: (v) => _goTo(v.round()),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white70,
                size: 20,
              ),
              onPressed: _currentPage < pages.length - 1
                  ? () => _goTo(_currentPage + 1)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
