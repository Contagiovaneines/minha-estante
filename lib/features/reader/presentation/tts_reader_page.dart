import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/storage/local_storage_service.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_item.dart';
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

  LibraryItem? _item;
  BookTextExtractionResult? _extraction;
  List<BookTextSegment> _segments = const [];
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
      await ref
          .read(libraryControllerProvider.notifier)
          .markItemOpened(item.id);
      final extraction = await _extractor.extract(item);
      final saved = _loadSavedProgress(item.id);

      if (!mounted) return;
      setState(() {
        _item = item;
        _extraction = extraction;
        _segments = extraction.segments;
        _currentIndex = _safeSegmentIndex(
          saved?.segmentIndex ?? 0,
          extraction.segments.length,
        );
        _language = saved?.language ?? _language;
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
      speechRate: _speechRate,
      updatedAt: DateTime.now(),
    );
    await LocalStorageService.saveTtsProgress(user.id, progress.toJson());
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;

    return Scaffold(
      backgroundColor: AppColors.background,
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
              style: const TextStyle(
                color: AppColors.textSecondary,
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
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_extraction?.sourceLabel ?? 'Texto'} - trecho ${_currentIndex + 1} de ${_segments.length}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: percent,
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: AppColors.border.withValues(alpha: 0.45),
                  color: AppColors.primary,
                ),
                const SizedBox(height: 24),
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
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: const InputDecoration(
              labelText: 'Voz',
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
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<double>(
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
        ),
      ],
    );
  }

  Widget _buildSegmentText(BookTextSegment segment) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            segment.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            segment.text,
            style: const TextStyle(
              color: AppColors.textSecondary,
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
}

class _TtsLanguage {
  final String label;
  final String code;

  const _TtsLanguage(this.label, this.code);
}
