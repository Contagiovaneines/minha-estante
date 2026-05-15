import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../library/domain/library_item.dart';
import '../../library/domain/reading_progress.dart';
import '../../library/presentation/library_controller.dart';

class AudiobookPlayerPage extends ConsumerStatefulWidget {
  final String itemId;
  const AudiobookPlayerPage({super.key, required this.itemId});

  @override
  ConsumerState<AudiobookPlayerPage> createState() =>
      _AudiobookPlayerPageState();
}

class _AudiobookPlayerPageState extends ConsumerState<AudiobookPlayerPage> {
  final _player = AudioPlayer();
  final _uuid = const Uuid();
  LibraryItem? _item;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final items = ref.read(libraryControllerProvider).value;
    if (items == null) return;
    final item = items.cast<LibraryItem?>().firstWhere(
      (e) => e?.id == widget.itemId,
      orElse: () => null,
    );
    if (item == null) return;

    await ref.read(libraryControllerProvider.notifier).markItemOpened(item.id);

    setState(() => _item = item);

    if (item.durationSeconds != null) {
      setState(() => _duration = Duration(seconds: item.durationSeconds!));
    }
    if (item.positionSeconds != null && item.positionSeconds! > 0) {
      setState(() => _position = Duration(seconds: item.positionSeconds!));
    }

    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state.playing);
      }
    });

    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.durationStream.listen((dur) {
      if (dur != null && mounted) setState(() => _duration = dur);
    });

    final url = item.remoteUrl ?? item.localPath;
    if (url == null) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Nenhuma fonte de áudio disponível para este item.';
      });
      return;
    }

    try {
      if (item.localPath != null) {
        await _player.setFilePath(item.localPath!);
      } else if (item.remoteUrl != null) {
        await _player.setUrl(item.remoteUrl!);
      }

      if (item.positionSeconds != null && item.positionSeconds! > 0) {
        await _player.seek(Duration(seconds: item.positionSeconds!));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage =
              'Não foi possível carregar o áudio. Verifique a fonte e tente novamente.';
        });
      }
    }
  }

  Future<void> _saveProgress() async {
    final item = _item;
    if (item == null) return;
    final user = ref.read(authControllerProvider).value;
    if (user == null) return;

    final total = _duration.inSeconds > 0 ? _duration.inSeconds : 1;
    final position = _position.inSeconds;
    final percent = (position / total).clamp(0.0, 1.0);

    final progress = ReadingProgress(
      id: _uuid.v4(),
      userId: user.id,
      itemId: item.id,
      currentPage: 0,
      totalPages: 0,
      percent: percent,
      positionSeconds: position,
      updatedAt: DateTime.now(),
    );

    await ref.read(libraryControllerProvider.notifier).saveProgress(progress);
  }

  @override
  void dispose() {
    _saveProgress();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_hasError) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seek(int seconds) async {
    if (_hasError) return;
    final newPos = _position + Duration(seconds: seconds);
    await _player.seek(newPos.isNegative ? Duration.zero : newPos);
  }

  void _changeSpeed() {
    final speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final idx = speeds.indexOf(_speed);
    final next = speeds[(idx + 1) % speeds.length];
    setState(() => _speed = next);
    _player.setSpeed(next);
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
                _buildCoverArt(item),
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
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.audioAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Áudio',
              style: TextStyle(
                color: AppColors.audioAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.more_vert_rounded,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverArt(LibraryItem item) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.audioAccent.withValues(alpha: 0.3),
            AppColors.audioAccent.withValues(alpha: 0.1),
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
    return Column(
      children: [
        Container(
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
        ),
      ],
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
            onChanged: (v) {
              final newPos = Duration(
                seconds: (v * _duration.inSeconds).toInt(),
              );
              _player.seek(newPos);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
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
              onPressed: () => _seek(-15),
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
              onPressed: () => _seek(15),
              icon: const Icon(
                Icons.forward_rounded,
                color: AppColors.textPrimary,
                size: 36,
              ),
              tooltip: 'Avançar 15s',
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {},
              icon: const Icon(
                Icons.list_rounded,
                color: AppColors.textSecondary,
              ),
              tooltip: 'Lista de capítulos',
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
