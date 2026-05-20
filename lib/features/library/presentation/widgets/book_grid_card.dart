import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_chip.dart';
import '../../../../core/widgets/progress_bar.dart';
import '../../domain/library_item.dart';
import 'library_item_cover.dart';

class BookGridCard extends StatelessWidget {
  final LibraryItem item;
  final VoidCallback onTap;

  const BookGridCard({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outline),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCover(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppChip(type: _chipType),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.author != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.author!,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (item.progress > 0) ...[
                    const SizedBox(height: 8),
                    AppProgressBar(
                      value: item.progress,
                      color: _progressColor(context),
                      height: 4,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${(item.progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 10,
                        color: _progressColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover() {
    return SizedBox(
      height: 130,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: LibraryItemCover(
              item: item,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
              iconSize: 52,
            ),
          ),
          if (item.isNew)
            const Positioned(
              top: 8,
              right: 8,
              child: AppChip(type: ChipType.newItem),
            ),
        ],
      ),
    );
  }

  Color _progressColor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    switch (item.type) {
      case ItemType.pdf:
        return colors.primary;
      case ItemType.hq:
        return AppColors.comicAccent;
      case ItemType.audio:
        return AppColors.audioAccent;
      case ItemType.ebook:
        return colors.primaryContainer;
      case ItemType.document:
        return AppColors.localAccent;
      case ItemType.text:
        return colors.onSurfaceVariant;
    }
  }

  ChipType get _chipType {
    switch (item.type) {
      case ItemType.pdf:
        return ChipType.pdf;
      case ItemType.hq:
        return ChipType.hq;
      case ItemType.audio:
        return ChipType.audio;
      case ItemType.ebook:
        return ChipType.ebook;
      case ItemType.document:
        return ChipType.document;
      case ItemType.text:
        return ChipType.text;
    }
  }
}
