import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_bottom_nav.dart';

class ScaffoldWithNav extends StatelessWidget {
  final Widget child;
  const ScaffoldWithNav({super.key, required this.child});

  int _locationToIndex(String location) {
    if (location.startsWith('/library')) return 0;
    if (location.startsWith('/audiobooks')) return 1;
    if (location.startsWith('/profile') || location.startsWith('/privacy')) {
      return 2;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _locationToIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: AppBottomNav(
        currentIndex: currentIndex,
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/library');
              break;
            case 1:
              context.go('/audiobooks');
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
