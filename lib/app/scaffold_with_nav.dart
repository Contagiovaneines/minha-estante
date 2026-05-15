import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_bottom_nav.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../core/storage/local_storage_service.dart';

class ScaffoldWithNav extends ConsumerWidget {
  final Widget child;
  const ScaffoldWithNav({super.key, required this.child});

  int _locationToIndex(String location, bool showSources) {
    if (location.startsWith('/library')) return 0;
    if (location.startsWith('/sources')) return showSources ? 1 : 0;
    if (location.startsWith('/profile')) return showSources ? 2 : 1;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final user = ref.watch(authControllerProvider).value;
    final showSources =
        user != null && LocalStorageService.isDriveEnabled(user.id);
    final currentIndex = _locationToIndex(location, showSources);

    return Scaffold(
      body: child,
      bottomNavigationBar: AppBottomNav(
        currentIndex: currentIndex,
        showSources: showSources,
        onTap: (index) {
          if (!showSources && index == 1) {
            context.go('/profile');
            return;
          }
          switch (index) {
            case 0:
              context.go('/library');
              break;
            case 1:
              context.go('/sources');
              break;
            case 2:
              context.go('/profile');
              break;
          }
        },
      ),
    );
  }
}
