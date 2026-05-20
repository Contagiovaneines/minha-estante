import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
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
import '../domain/book_tts_progress.dart';

class TtsReaderPage extends ConsumerStatefulWidget {
  final String itemId;

  const TtsReaderPage({super.key, required this.itemId});

  @override
  ConsumerState<TtsReaderPage> createState() => _TtsReaderPageState();
}

class _TtsReaderPageState extends ConsumerState<TtsReaderPage> {
  static const _languages = [
    _TtsLanguage('Portugues', 'pt-BR'),
    _TtsLanguage('Ingles', 'en-US'),
    _TtsLanguage('Espanhol', 'es-ES'),
  ];

  static const _speechRates = [0.35, 0.45, 0.55, 0.65];

  final _tts = FlutterTts();
  final _extractor = BookTextExtractor();
  final _uuid = const Uuid();

  LibraryItem? _item;
  BookTextExtractionResult? _extraction;
  List<BookTextSegment> _segments = const [];
  List<_TtsVoice> _voices = const [];
  _TtsVoice? _selectedVoice;
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isPlaying = false;
  String? _errorMessage;
  String _language = 'pt-BR';
  double _speechRate = 0.45;
  int _playToken = 0;

  @override
  void initState() {
    super.initState();
    _configureTts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _playToken++;
    unawaited(_tts.stop());
    unawaited(_saveProgress());
    super.dispose();
  }

  Future<void> _configureTts() async {
    _tts.setErrorHandler((message) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _errorMessage = 'Erro no TTS: $message';
      });
    });
    unawaited(_loadVoices());
  }

  Future<void> _loadVoices() async {
    try {
      final rawVoices = await _tts.getVoices;
      final voices = _parseVoices(rawVoices);
      if (!mounted || voices.isEmpty) return;
      setState(() => _voices = voices);
    } catch (_) {
      // Alguns engines TTS nao expoem a lista de vozes.
    }
  }

  Future<void> _load() async {
    final items = ref.read(libraryControllerProvider).value;
    final item = items?.cast<LibraryItem?>().firstWhere(
      (entry) => entry?.id == widget.itemId,
      orElse: () => null,
    );

    if (item == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Livro nao encontrado.';
      });
      return;
    }

    try {
      var playableItem = item;
      if (item.type == ItemType.pdf && item.localPath != null) {
        final resolvedFile = await SafFileResolver.resolveForProcessing(
          item.localPath!,
        );
        playableItem = item.copyWith(localPath: resolvedFile.path);
      }

      await ref
          .read(libraryControllerProvider.notifier)
          .markItemOpened(playableItem.id);
      final extraction = await _extractor.extract(playableItem);
      final saved = _loadSavedProgress(playableItem.id);
      final readingProgress = await ref
          .read(libraryControllerProvider.notifier)
          .getProgress(playableItem.id);
      final selectedVoice = _voiceFromSaved(saved);

      if (!mounted) return;
      setState(() {
        _item = playableItem;
        _extraction = extraction;
        _segments = extraction.segments;
        _currentIndex = _initialSegmentIndex(
          saved: saved,
          readingProgress: readingProgress,
          segments: extraction.segments,
        );
        _language = saved?.language ?? _language;
        _selectedVoice = selectedVoice;
        _speechRate = _normalizeSpeechRate(saved?.speechRate ?? _speechRate);
        _isLoading = false;
        _errorMessage = null;
      });

      await _applyTtsSettings();
    } on BookTextExtractionException catch (error) {
      if (!mounted) return;
      setState(() {
        _item = item;
        _isLoading = false;
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _item = item;
        _isLoading = false;
        _errorMessage =
            'Nao foi possivel preparar este livro para ouvir: $error';
      });
    }
  }

  BookTtsProgress? _loadSavedProgress(String itemId) {
    final user = ref.read(authControllerProvider).value;
    if (user == null) return null;
    final raw = LocalStorageService.getTtsProgress(user.id, itemId);
    return raw == null ? null : BookTtsProgress.fromJson(raw);
  }

  Future<void> _applyTtsSettings() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(_speechRate);
    try {
      await _tts.setLanguage(_language);
    } catch (_) {
      // Alguns aparelhos nao tem todas as vozes instaladas.
    }
    final voice = _selectedVoice;
    if (voice != null) {
      try {
        await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
      } catch (_) {
        // Se a voz nao estiver disponivel, o sistema usa a padrao do idioma.
      }
    }
    try {
      await _tts.setQueueMode(0);
    } catch (_) {
      // setQueueMode e especifico do Android.
    }
  }

  Future<void> _play() async {
    if (_segments.isEmpty || _isPlaying) return;
    final token = ++_playToken;
    setState(() {
      _isPlaying = true;
      _errorMessage = null;
    });

    try {
      await _applyTtsSettings();
      while (mounted &&
          _isPlaying &&
          token == _playToken &&
          _currentIndex < _segments.length) {
        await _saveProgress();
        await _tts.speak(_segments[_currentIndex].text, focus: true);
        if (!mounted || !_isPlaying || token != _playToken) return;

        if (_currentIndex >= _segments.length - 1) {
          setState(() => _isPlaying = false);
          await _saveProgress(completed: true);
          return;
        }

        setState(() => _currentIndex++);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _errorMessage = 'Erro ao reproduzir TTS: $error';
      });
    }
  }

  Future<void> _pause() async {
    if (!_isPlaying) return;
    _playToken++;
    setState(() => _isPlaying = false);
    try {
      await _tts.pause();
    } catch (_) {
      await _tts.stop();
    }
    await _saveProgress();
  }

  Future<void> _stopAndReset() async {
    _playToken++;
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _currentIndex = 0;
    });
    await _saveProgress();
  }

  Future<void> _jumpBy(int delta) async {
    if (_segments.isEmpty) return;
    final wasPlaying = _isPlaying;
    _playToken++;
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _currentIndex = (_currentIndex + delta).clamp(0, _segments.length - 1);
    });
    await _saveProgress();
    if (wasPlaying) unawaited(_play());
  }

  Future<void> _changeLanguage(String language) async {
    final wasPlaying = _isPlaying;
    _playToken++;
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _language = language;
      _selectedVoice = _firstVoiceForLanguage(language);
    });
    await _applyTtsSettings();
    await _saveProgress();
    if (wasPlaying) unawaited(_play());
  }

  Future<void> _changeSpeechRate(double value) async {
    final wasPlaying = _isPlaying;
    _playToken++;
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _speechRate = value;
    });
    await _applyTtsSettings();
    await _saveProgress();
    if (wasPlaying) unawaited(_play());
  }

  Future<void> _changeVoice(String voiceId) async {
    final voice = _voiceById(voiceId);
    if (voice == null) return;

    final wasPlaying = _isPlaying;
    _playToken++;
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _selectedVoice = voice;
      _language = voice.locale;
    });
    await _applyTtsSettings();
    await _saveProgress();
    if (wasPlaying) unawaited(_play());
  }

  Future<void> _saveProgress({bool completed = false}) async {
    final item = _item;
    final user = ref.read(authControllerProvider).value;
    if (item == null || user == null || _segments.isEmpty) return;

    final segmentIndex = completed
        ? _segments.length - 1
        : _currentIndex.clamp(0, _segments.length - 1);
    final percent = completed
        ? 1.0
        : (segmentIndex / _segments.length).clamp(0.0, 1.0).toDouble();

    final progress = BookTtsProgress(
      itemId: item.id,
      segmentIndex: segmentIndex,
      totalSegments: _segments.length,
      percent: percent,
      language: _language,
      voiceName: _selectedVoice?.name,
      voiceLocale: _selectedVoice?.locale,
      speechRate: _speechRate,
      updatedAt: DateTime.now(),
    );
    await LocalStorageService.saveTtsProgress(user.id, progress.toJson());

    final segment = _segments[segmentIndex];
    final totalPages = _totalPagesForProgress(item);
    final page = segment.pageNumber ?? item.currentPage;
    final syncedPercent = item.type == ItemType.pdf && page > 0
        ? (page / totalPages).clamp(0.0, 1.0).toDouble()
        : percent;

    await ref
        .read(libraryControllerProvider.notifier)
        .saveProgress(
          ReadingProgress(
            id: _uuid.v4(),
            userId: user.id,
            itemId: item.id,
            currentPage: item.type == ItemType.pdf
                ? page.clamp(1, totalPages).toInt()
                : 0,
            totalPages: item.type == ItemType.pdf ? totalPages : 0,
            percent: syncedPercent,
            updatedAt: DateTime.now(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () async {
            await _pause();
            if (!context.mounted) return;
            context.pop();
          },
        ),
        title: Text(
          item?.title ?? 'Ouvir livro',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _errorMessage != null
            ? _buildMessage(_errorMessage!)
            : _buildPlayer(),
      ),
    );
  }

  Widget _buildMessage(String message) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.record_voice_over_rounded,
              size: 56,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    final item = _item!;
    final segment = _segments[_currentIndex];
    final percent = ((_currentIndex + 1) / _segments.length).clamp(0.0, 1.0);
    final colors = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_extraction?.sourceLabel ?? 'Texto'} - trecho ${_currentIndex + 1} de ${_segments.length}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: percent,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: colors.outlineVariant.withValues(
                    alpha: 0.55,
                  ),
                  color: AppColors.primary,
                ),
                const SizedBox(height: 24),
                if (item.type == ItemType.pdf) ...[
                  _buildPdfPreview(item, segment),
                  const SizedBox(height: 22),
                ],
                _buildControls(),
                const SizedBox(height: 22),
                _buildSettings(),
                const SizedBox(height: 24),
                _buildSegmentText(segment),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          onPressed: _currentIndex == 0 ? null : () => _jumpBy(-1),
          tooltip: 'Trecho anterior',
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 18),
        SizedBox(
          width: 76,
          height: 76,
          child: IconButton.filled(
            onPressed: _isPlaying ? _pause : _play,
            tooltip: _isPlaying ? 'Pausar' : 'Ouvir',
            iconSize: 38,
            icon: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
        ),
        const SizedBox(width: 18),
        IconButton.filledTonal(
          onPressed: _currentIndex >= _segments.length - 1
              ? null
              : () => _jumpBy(1),
          tooltip: 'Proximo trecho',
          icon: const Icon(Icons.skip_next_rounded),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _stopAndReset,
          tooltip: 'Voltar ao inicio',
          icon: const Icon(Icons.restart_alt_rounded),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    final voices = _voicesForLanguage;
    final selectedVoiceId =
        voices.any((voice) => voice.id == _selectedVoice?.id)
        ? _selectedVoice?.id
        : null;

    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _language,
          decoration: const InputDecoration(
            labelText: 'Idioma',
            prefixIcon: Icon(Icons.language_rounded),
          ),
          items: [
            for (final language in _languages)
              DropdownMenuItem(
                value: language.code,
                child: Text(language.label),
              ),
          ],
          onChanged: (value) {
            if (value != null) unawaited(_changeLanguage(value));
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: selectedVoiceId,
          decoration: const InputDecoration(
            labelText: 'Voz do aparelho',
            prefixIcon: Icon(Icons.record_voice_over_rounded),
          ),
          hint: const Text('Voz padrao do sistema'),
          items: [
            for (final voice in voices)
              DropdownMenuItem(
                value: voice.id,
                child: Text(voice.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: voices.isEmpty
              ? null
              : (value) {
                  if (value != null) unawaited(_changeVoice(value));
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<double>(
          initialValue: _speechRate,
          decoration: const InputDecoration(
            labelText: 'Velocidade',
            prefixIcon: Icon(Icons.speed_rounded),
          ),
          items: [
            for (final rate in _speechRates)
              DropdownMenuItem(
                value: rate,
                child: Text(_speechRateLabel(rate)),
              ),
          ],
          onChanged: (value) {
            if (value != null) unawaited(_changeSpeechRate(value));
          },
        ),
      ],
    );
  }

  Widget _buildPdfPreview(LibraryItem item, BookTextSegment segment) {
    final pageNumber = segment.pageNumber ?? item.currentPage.clamp(1, 999999);
    final localPath = item.localPath?.trim();
    final remoteUrl = item.remoteUrl?.trim();

    final Widget preview;
    if (localPath != null && localPath.isNotEmpty) {
      preview = PdfDocumentViewBuilder.file(
        localPath,
        loadingBuilder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        errorBuilder: (_, _, _) => _buildPdfPreviewError(),
        builder: (context, document) =>
            _buildPdfPreviewPage(document, pageNumber),
      );
    } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
      preview = PdfDocumentViewBuilder.uri(
        Uri.parse(remoteUrl),
        loadingBuilder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        errorBuilder: (_, _, _) => _buildPdfPreviewError(),
        builder: (context, document) =>
            _buildPdfPreviewPage(document, pageNumber),
      );
    } else {
      preview = _buildPdfPreviewError();
    }

    return SizedBox(
      height: 430,
      child: ClipRRect(borderRadius: BorderRadius.circular(18), child: preview),
    );
  }

  Widget _buildPdfPreviewPage(PdfDocument? document, int pageNumber) {
    if (document == null || document.pages.isEmpty) {
      return _buildPdfPreviewError();
    }

    final safePage = pageNumber.clamp(1, document.pages.length);
    return ColoredBox(
      color: Colors.black,
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(
          child: PdfPageView(
            key: ValueKey('tts_pdf_page_$safePage'),
            document: document,
            pageNumber: safePage,
            backgroundColor: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildPdfPreviewError() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: Text(
        'Nao foi possivel mostrar a pagina do PDF.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildSegmentText(BookTextSegment segment) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            segment.title,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            segment.text,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontSize: 16,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  int _safeSegmentIndex(int index, int total) {
    if (total <= 0) return 0;
    return index.clamp(0, total - 1);
  }

  int _initialSegmentIndex({
    required BookTtsProgress? saved,
    required ReadingProgress? readingProgress,
    required List<BookTextSegment> segments,
  }) {
    if (segments.isEmpty) return 0;

    final shouldUseReadingProgress =
        readingProgress != null &&
        (saved == null || readingProgress.updatedAt.isAfter(saved.updatedAt));

    if (shouldUseReadingProgress) {
      final page = readingProgress.currentPage;
      if (page > 0) {
        final exactIndex = segments.indexWhere(
          (segment) => segment.pageNumber == page,
        );
        if (exactIndex >= 0) return exactIndex;

        final nextIndex = segments.indexWhere(
          (segment) => (segment.pageNumber ?? 0) > page,
        );
        if (nextIndex > 0) return nextIndex - 1;
      }

      if (readingProgress.percent > 0) {
        return _safeSegmentIndex(
          (readingProgress.percent * segments.length).floor(),
          segments.length,
        );
      }
    }

    return _safeSegmentIndex(saved?.segmentIndex ?? 0, segments.length);
  }

  int _totalPagesForProgress(LibraryItem item) {
    if (item.totalPages > 0) return item.totalPages;
    final pages = _segments
        .map((segment) => segment.pageNumber ?? 0)
        .where((page) => page > 0);
    if (pages.isEmpty) return 1;
    return pages.reduce((a, b) => a > b ? a : b);
  }

  double _normalizeSpeechRate(double value) {
    return _speechRates.reduce(
      (closest, rate) =>
          (rate - value).abs() < (closest - value).abs() ? rate : closest,
    );
  }

  String _speechRateLabel(double rate) {
    if (rate == 0.35) return '0.8x';
    if (rate == 0.45) return '1.0x';
    if (rate == 0.55) return '1.2x';
    return '1.4x';
  }

  List<_TtsVoice> get _voicesForLanguage {
    final filtered = _voices
        .where(
          (voice) =>
              voice.locale.toLowerCase().startsWith(_language.toLowerCase()),
        )
        .toList();
    return filtered.isEmpty ? _voices : filtered;
  }

  _TtsVoice? _firstVoiceForLanguage(String language) {
    for (final voice in _voices) {
      if (voice.locale.toLowerCase().startsWith(language.toLowerCase())) {
        return voice;
      }
    }
    return null;
  }

  _TtsVoice? _voiceById(String voiceId) {
    for (final voice in _voices) {
      if (voice.id == voiceId) return voice;
    }
    return null;
  }

  _TtsVoice? _voiceFromSaved(BookTtsProgress? saved) {
    if (saved?.voiceName == null || saved?.voiceLocale == null) return null;
    for (final voice in _voices) {
      if (voice.name == saved!.voiceName && voice.locale == saved.voiceLocale) {
        return voice;
      }
    }
    return _TtsVoice(name: saved!.voiceName!, locale: saved.voiceLocale!);
  }

  List<_TtsVoice> _parseVoices(dynamic rawVoices) {
    if (rawVoices is! List) return const [];
    final voices = <_TtsVoice>[];
    final seen = <String>{};

    for (final raw in rawVoices) {
      String? name;
      String? locale;
      if (raw is Map) {
        name = raw['name']?.toString();
        locale = (raw['locale'] ?? raw['language'])?.toString();
      }
      if (name == null || name.trim().isEmpty) continue;
      locale = (locale == null || locale.trim().isEmpty) ? _language : locale;

      final voice = _TtsVoice(name: name.trim(), locale: locale.trim());
      if (seen.add(voice.id)) voices.add(voice);
    }

    voices.sort((a, b) => a.label.compareTo(b.label));
    return voices;
  }
}

class _TtsLanguage {
  final String label;
  final String code;

  const _TtsLanguage(this.label, this.code);
}

class _TtsVoice {
  final String name;
  final String locale;

  const _TtsVoice({required this.name, required this.locale});

  String get id => '$locale::$name';

  String get label => '${name.replaceAll('_', ' ')} ($locale)';
}
