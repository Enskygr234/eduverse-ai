import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screens.dart';
import '../features/courses/course_detail_screen.dart';
import '../features/courses/courses_screen.dart';
import '../features/home/home_screen.dart';
import '../features/home/shell.dart';
import '../features/lesson/lesson_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import 'providers.dart';

/// Bridges Riverpod session changes to GoRouter's redirect logic.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (_, __) => notifyListeners());
  }
}

const _publicPaths = {'/welcome', '/login', '/register'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final path = state.matchedLocation;
      // Only the very first load (or a failed first load) shows the splash; later
      // refreshes keep the previous value and must not bounce the user around.
      final s = session.valueOrNull;
      if (s == null) return path == '/splash' ? null : '/splash';
      if (!s.signedIn) return _publicPaths.contains(path) ? null : '/welcome';
      if (s.needsOnboarding) return path == '/onboarding' ? null : '/onboarding';
      if (_publicPaths.contains(path) || path == '/splash' || path == '/onboarding') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/courses', builder: (_, __) => const CoursesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
      GoRoute(
        path: '/course/:slug',
        builder: (_, state) => CourseDetailScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/lesson/:id',
        builder: (_, state) => LessonScreen(lessonId: state.pathParameters['id']!),
      ),
    ],
  );
});
