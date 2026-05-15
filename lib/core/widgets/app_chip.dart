import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

enum ChipType { pdf, hq, audio, ebook, document, text, newItem, online, local }

class AppChip extends StatelessWidget {
  final ChipType type;
  final String? customLabel;

  const AppChip({super.key, required this.type, this.customLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _backgroundColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _backgroundColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        customLabel ?? _label,
        style: TextStyle(
          color: _backgroundColor,
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

  Color get _backgroundColor {
    switch (type) {
      case ChipType.pdf:
        return AppColors.primary;
      case ChipType.hq:
        return AppColors.comicAccent;
      case ChipType.audio:
        return AppColors.audioAccent;
      case ChipType.ebook:
        return AppColors.primaryContainer;
      case ChipType.document:
        return AppColors.localAccent;
      case ChipType.text:
        return AppColors.textSecondary;
      case ChipType.newItem:
        return AppColors.primaryContainer;
      case ChipType.online:
        return AppColors.primaryContainer;
      case ChipType.local:
        return AppColors.localAccent;
    }
  }
}
