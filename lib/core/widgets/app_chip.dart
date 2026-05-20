import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

enum ChipType { pdf, hq, audio, ebook, document, text, newItem, online, local }

class AppChip extends StatelessWidget {
  final ChipType type;
  final String? customLabel;

  const AppChip({super.key, required this.type, this.customLabel});

  @override
  Widget build(BuildContext context) {
    final color = _color(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        customLabel ?? _label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String get _label {
    switch (type) {
      case ChipType.pdf:
        return 'PDF';
      case ChipType.hq:
        return 'HQ';
      case ChipType.audio:
        return 'Audio';
      case ChipType.ebook:
        return 'Ebook';
      case ChipType.document:
        return 'DOC';
      case ChipType.text:
        return 'TXT';
      case ChipType.newItem:
        return 'NOVO';
      case ChipType.online:
        return 'Online';
      case ChipType.local:
        return 'Celular';
    }
  }

  Color _color(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    switch (type) {
      case ChipType.pdf:
        return colors.primary;
      case ChipType.hq:
        return AppColors.comicAccent;
      case ChipType.audio:
        return AppColors.audioAccent;
      case ChipType.ebook:
        return colors.primaryContainer;
      case ChipType.document:
        return AppColors.localAccent;
      case ChipType.text:
        return colors.onSurfaceVariant;
      case ChipType.newItem:
        return colors.primaryContainer;
      case ChipType.online:
        return colors.primaryContainer;
      case ChipType.local:
        return AppColors.localAccent;
    }
  }
}
