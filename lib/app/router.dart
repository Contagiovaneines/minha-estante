import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/auth/presentation/drive_setup_page.dart';
import '../features/splash/presentation/splash_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/library/presentation/local_collection_page.dart';
import '../features/sources/presentation/sources_page.dart';
import '../features/sources/presentation/add_drive_source_page.dart';
import '../features/book_detail/presentation/book_detail_page.dart';
import '../features/reader/presentation/pdf_reader_page.dart';
import '../features/reader/presentation/document_reader_page.dart';
import '../features/reader/presentation/epub_reader_page.dart';
import '../features/reader/presentation/hq_reader_page.dart';
import '../features/reader/presentation/cbr_conversion_page.dart';
import '../features/library/domain/library_item.dart';
import '../features/audio/presentation/audiobook_player_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../../../core/storage/local_storage_service.dart';
import 'scaffold_with_nav.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isSplash = state.matchedLocation == '/splash';
      if (authState.isLoading) return isSplash ? null : '/splash';

      final isLoggedIn = authState.value != null;
      final isAuthRoute =
          state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn) {
        final userId = authState.value!.id;
        final hasSetup = LocalStorageService.hasDriveSetup(userId);

        if (!hasSetup && state.matchedLocation != '/drive_setup') {
          return '/drive_setup';
        }

        if (hasSetup && (isAuthRoute || isSplash)) {
          return '/library';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/drive_setup',
        builder: (context, state) => const DriveSetupPage(),
      ),
      GoRoute(
        path: '/book/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return BookDetailPage(itemId: id);
        },
      ),
      GoRoute(
        path: '/collection/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return LocalCollectionPage(collectionId: id);
        },
      ),
      GoRoute(
        path: '/reader/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PdfReaderPage(itemId: id);
        },
      ),
      GoRoute(
        path: '/document/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return DocumentReaderPage(itemId: id);
        },
      ),
      GoRoute(
        path: '/epub/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return EpubReaderPage(itemId: id);
        },
      ),
      GoRoute(
        path: '/hq/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return HqReaderPage(itemId: id);
        },
      ),
      // Rota usada após conversão CBR→CBZ: recebe LibraryItem via extra
      GoRoute(
        path: '/hq_from_path',
        builder: (context, state) {
          final item = state.extra as LibraryItem;
          return CbrConversionPage(item: item);
        },
      ),
      GoRoute(
        path: '/audio/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return AudiobookPlayerPage(itemId: id);
        },
      ),
      ShellRoute(
        builder: (context, state, child) => ScaffoldWithNav(child: child),
        routes: [
          GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryPage(),
          ),
          GoRoute(
            path: '/sources',
            builder: (context, state) => const SourcesPage(),
          ),
          GoRoute(
            path: '/sources/add',
            builder: (context, state) => const AddDriveSourcePage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
    ],
  );
});
