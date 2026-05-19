import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_item.dart';
import '../../library/domain/reading_progress.dart';
import '../../library/presentation/library_controller.dart';

final audiobookAudioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(player.dispose);
  return player;
});

final currentAudiobookItemIdProvider =
    NotifierProvider<CurrentAudiobookItemId, String?>(
      CurrentAudiobookItemId.new,
    );

class CurrentAudiobookItemId extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? itemId) => state = itemId;
}

class AudiobookPlayerPage extends ConsumerStatefulWidget {
  final String itemId;

  const AudiobookPlayerPage({super.key, required this.itemId});

  @override
  ConsumerState<AudiobookPlayerPage> createState() =>
      _AudiobookPlayerPageState();
}

class _AudiobookPlayerPageState extends ConsumerState<AudiobookPlayerPage> {
  late final AudioPlayer _player;
  final _uuid = const Uuid();
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  LibraryItem? _item;
  bool _isPlaying = false;
  bool _hasError = false;
  bool _isSaving = false;
  String _errorMessage = '';
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  DateTime _lastAutoSave = DateTime.fromMillisecondsSinceEpoch(0);
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _player = ref.read(audiobookAudioPlayerProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    unawaited(_saveProgress());
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    final items = ref.read(libraryControllerProvider).value;
    if (items == null) return;

    final item = items.cast<LibraryItem?>().firstWhere(
      (entry) => entry?.id == widget.itemId,
      orElse: () => null,
    );
    if (item == null) return;

    await ref.read(libraryControllerProvider.notifier).markItemOpened(item.id);

    setState(() {
      _item = item;
      _duration = item.durationSeconds != null
          ? Duration(seconds: item.durationSeconds!)
          : Duration.zero;
      _position = item.positionSeconds != null
          ? Duration(seconds: item.positionSeconds!)
          : Duration.zero;
    });

    final sourceUri = _sourceUriFor(item);
    if (sourceUri == null) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Nenhuma fonte de audio disponivel para este item.';
      });
      return;
    }

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());

      _attachPlayerListeners();

      final currentItemId = ref.read(currentAudiobookItemIdProvider);
      if (currentItemId != item.id) {
        await _player.setAudioSource(
          AudioSource.uri(sourceUri, tag: _mediaItemFor(item)),
          initialPosition: _position,
        );
        ref.read(currentAudiobookItemIdProvider.notifier).set(item.id);
      } else {
        setState(() {
          _position = _player.position;
          _duration = _player.duration ?? _duration;
          _isPlaying = _player.playing;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage =
            'Nao foi possivel carregar o audio. Verifique o arquivo e tente novamente.';
      });
    }
  }

  void _attachPlayerListeners() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();

    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state.playing);
      if (!state.playing) unawaited(_saveProgress());
    });

    _positionSub = _player.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);

      final now = DateTime.now();
      if (now.difference(_lastAutoSave).inSeconds >= 20) {
        _lastAutoSave = now;
        unawaited(_saveProgress());
      }
    });

    _durationSub = _player.durationStream.listen((duration) {
      if (duration == null || !mounted) return;
      setState(() => _duration = duration);
    });
  }

  Future<void> _saveProgress() async {
    final item = _item;
    final user = ref.read(authControllerProvider).value;
    if (item == null || user == null || _isSaving) return;
    final libraryController = ref.read(libraryControllerProvider.notifier);

    _isSaving = true;
    try {
      final total = _duration.inSeconds > 0 ? _duration.inSeconds : 1;
      final position = _position.inSeconds.clamp(0, total);
      final percent = (position / total).clamp(0.0, 1.0);

      final updatedItem = item.copyWith(
        durationSeconds: _duration.inSeconds > 0
            ? _duration.inSeconds
            : item.durationSeconds,
        positionSeconds: position,
        progress: percent,
        updatedAt: DateTime.now(),
      );
      _item = updatedItem;

      await libraryController.updateItem(updatedItem);
      await libraryController.saveProgress(
        ReadingProgress(
          id: _uuid.v4(),
          userId: user.id,
          itemId: item.id,
          currentPage: 0,
          totalPages: 0,
          percent: percent,
          positionSeconds: position,
          updatedAt: DateTime.now(),
        ),
      );
    } finally {
      _isSaving = false;
    }
  }

  Uri? _sourceUriFor(LibraryItem item) {
    if (item.localPath != null && item.localPath!.trim().isNotEmpty) {
      return Uri.file(item.localPath!);
    }
    if (item.remoteUrl != null && item.remoteUrl!.trim().isNotEmpty) {
      return Uri.parse(item.remoteUrl!);
    }
    return null;
  }

  MediaItem _mediaItemFor(LibraryItem item) {
    return MediaItem(
      id: item.id,
      album: 'Minha Estante',
      title: item.title,
      artist: item.author ?? 'Audiobook',
      duration: item.durationSeconds != null
          ? Duration(seconds: item.durationSeconds!)
          : null,
    );
  }

  Future<void> _togglePlay() async {
    if (_hasError) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seekBy(int seconds) async {
    if (_hasError) return;
    final target = _position + Duration(seconds: seconds);
    await _player.seek(target.isNegative ? Duration.zero : target);
  }

  Future<void> _changeSpeed() async {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final index = speeds.indexOf(_speed);
    final next = speeds[(index + 1) % speeds.length];
    setState(() => _speed = next);
    await _player.setSpeed(next);
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: item == null
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.audioAccent),
              )
            : _buildPlayer(item),
      ),
    );
  }

  Widget _buildPlayer(LibraryItem item) {
    return Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 24),
                _buildCoverArt(),
                const SizedBox(height: 32),
                Text(
                  item.title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (item.author != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.author!,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                if (_hasError) _buildErrorView() else _buildControls(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () async {
              await _saveProgress();
              if (!context.mounted) return;
              context.pop();
            },
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textPrimary,
              size: 28,
            ),
            tooltip: 'Minimizar',
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.audioAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Audio',
              style: TextStyle(
                color: AppColors.audioAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => context.go('/audiobooks'),
            icon: const Icon(
              Icons.library_music_rounded,
              color: AppColors.textPrimary,
            ),
            tooltip: 'Audiobooks',
          ),
        ],
      ),
    );
  }

  Widget _buildCoverArt() {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.audioAccent.withValues(alpha: 0.30),
            AppColors.audioAccent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.audioAccent.withValues(alpha: 0.2),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Icon(
        Icons.headphones_rounded,
        size: 90,
        color: AppColors.audioAccent,
      ),
    );
  }

  Widget _buildErrorView() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.error,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final progressValue = _duration.inSeconds > 0
        ? (_position.inSeconds / _duration.inSeconds).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.audioAccent,
            inactiveTrackColor: AppColors.border,
            thumbColor: AppColors.audioAccent,
            overlayColor: AppColors.audioAccent.withValues(alpha: 0.15),
            trackHeight: 4,
          ),
          child: Slider(
            value: progressValue.toDouble(),
            onChanged: _duration.inSeconds == 0
                ? null
                : (value) {
                    final target = Duration(
                      seconds: (value * _duration.inSeconds).toInt(),
                    );
                    _player.seek(target);
                  },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              Formatters.formatDuration(_position.inSeconds),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              Formatters.formatDuration(_duration.inSeconds),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _changeSpeed,
              icon: Text(
                '${_speed}x',
                style: const TextStyle(
                  color: AppColors.audioAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              tooltip: 'Velocidade',
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _seekBy(-15),
              icon: const Icon(
                Icons.replay_rounded,
                color: AppColors.textPrimary,
                size: 36,
              ),
              tooltip: 'Voltar 15s',
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.audioAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.audioAccent.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: () => _seekBy(15),
              icon: const Icon(
                Icons.forward_rounded,
                color: AppColors.textPrimary,
                size: 36,
              ),
              tooltip: 'Avancar 15s',
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Pode bloquear a tela ou trocar de aba enquanto o audio toca.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
