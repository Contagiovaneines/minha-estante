import 'package:flutter/material.dart';

class LibraryTabs extends StatelessWidget {
  final TabController controller;

  const LibraryTabs({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return TabBar(
      controller: controller,
      labelColor: colors.primary,
      unselectedLabelColor: colors.onSurfaceVariant,
      indicatorColor: colors.primary,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      tabs: const [
        Tab(text: 'Online'),
        Tab(text: 'Celular'),
      ],
    );
  }
}
