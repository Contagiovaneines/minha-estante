import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ads_provider.dart';

class FakeMonetizationSlot extends ConsumerStatefulWidget {
  final String placement;

  const FakeMonetizationSlot({super.key, required this.placement});

  @override
  ConsumerState<FakeMonetizationSlot> createState() => _FakeMonetizationSlotState();
}

class _FakeMonetizationSlotState extends ConsumerState<FakeMonetizationSlot> {
  static const _allowedPlacements = [
    'library_home',
    'audiobooks_list',
    'audio_player_bottom',
    'profile_bottom',
  ];

  @override
  Widget build(BuildContext context) {
    final showAds = ref.watch(adsProvider);
    if (!showAds) return const SizedBox.shrink();

    if (!_allowedPlacements.contains(widget.placement)) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('🔗 Redirecionando para o vídeo... (Teste)'),
            backgroundColor: colors.primary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        height: 72,
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.outline.withValues(alpha: 0.2),
          ),
          image: const DecorationImage(
            image: NetworkImage(
              'https://img.youtube.com/vi/DKexiRt4PSw/hqdefault.jpg',
            ),
            fit: BoxFit.cover,
            opacity: 0.75,
          ),
        ),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Publicidade',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Assistir Trailer',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
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
