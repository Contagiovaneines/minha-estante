import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_chip.dart';
import '../../../../core/widgets/progress_bar.dart';
import '../../../reader/domain/ebook_format_support.dart';
import '../../domain/library_item.dart';
import 'library_item_cover.dart';

class ContinueReadingCard extends StatelessWidget {
  final LibraryItem item;

  const ContinueReadingCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(_routeForItem),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildCover(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppChip(type: _chipType),
                        const SizedBox(height: 8),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.author != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.author!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppProgressBar(
                          value: item.progress,
                          color: _coverColor,
                          height: 5,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: ElevatedButton(
                            onPressed: () => context.push(_routeForItem),
                            style: ElevatedButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: const Text('Continuar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover() {
    return SizedBox(
      width: 110,
      height: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: LibraryItemCover(
              item: item,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                bottomLeft: Radius.circular(24),
              ),
              iconSize: 48,
            ),
          ),
          if (item.isNew)
            const Positioned(
              top: 10,
              left: 10,
              child: AppChip(type: ChipType.newItem),
            ),
        ],
      ),
    );
  }

  Color get _coverColor {
    switch (item.type) {
      case ItemType.pdf:
        return AppColors.primary;
      case ItemType.hq:
        return AppColors.comicAccent;
      case ItemType.audio:
        return AppColors.audioAccent;
      case ItemType.ebook:
        return AppColors.primaryContainer;
      case ItemType.document:
        return AppColors.localAccent;
      case ItemType.text:
        return AppColors.textSecondary;
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

  String get _routeForItem {
    switch (item.type) {
      case ItemType.audio:
        return '/audio/${item.id}';
      case ItemType.pdf:
        return '/reader/${item.id}';
      case ItemType.hq:
        return '/hq/${item.id}';
      case ItemType.ebook:
        return EbookFormatSupport.canReadInternally(item)
            ? '/epub/${item.id}'
            : '/document/${item.id}';
      case ItemType.document:
      case ItemType.text:
        return '/document/${item.id}';
    }
  }
}
