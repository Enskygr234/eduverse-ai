import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../data/models/models.dart';

/// Overridden in main() with the remote or offline implementation.
final backendProvider = Provider<EduverseBackend>((ref) => throw UnimplementedError('backendProvider not overridden'));

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class SessionState {
  const SessionState({this.me});
  final Me? me;
  bool get signedIn => me != null;
  bool get needsOnboarding => me != null && !me!.onboardingCompleted;
}

class SessionController extends AsyncNotifier<SessionState> {
  EduverseBackend get _backend => ref.read(backendProvider);

  @override
  Future<SessionState> build() async {
    if (!await _backend.hasSession()) return const SessionState();
    try {
      return SessionState(me: await _backend.me());
    } on BackendException catch (e) {
      if (e.isUnauthorized) {
        await _backend.logout();
        return const SessionState();
      }
      rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    await _backend.login(email: email, password: password);
    state = AsyncData(SessionState(me: await _backend.me()));
  }

  Future<void> register(String email, String password, String displayName) async {
    await _backend.register(email: email, password: password, displayName: displayName);
    state = AsyncData(SessionState(me: await _backend.me()));
  }

  Future<void> completeOnboarding(OnboardingAnswers answers) async {
    await _backend.completeOnboarding(answers);
    state = AsyncData(SessionState(me: await _backend.me()));
  }

  Future<void> refreshMe() async {
    state = AsyncData(SessionState(me: await _backend.me()));
  }

  Future<void> logout() async {
    await _backend.logout();
    state = const AsyncData(SessionState());
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, SessionState>(SessionController.new);

final dashboardProvider = FutureProvider.autoDispose<Dashboard>((ref) => ref.watch(backendProvider).dashboard());

final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) => ref.watch(backendProvider).categories());

final coursesProvider = FutureProvider.autoDispose.family<List<CourseSummary>, String?>(
  (ref, category) => ref.watch(backendProvider).courses(category: category),
);

final courseProvider = FutureProvider.autoDispose.family<CourseDetail, String>(
  (ref, slug) => ref.watch(backendProvider).course(slug),
);

/// Call after anything that changes progress (lesson completion) so every screen refreshes.
void invalidateProgress(WidgetRef ref) {
  ref.invalidate(dashboardProvider);
  ref.invalidate(coursesProvider);
  ref.invalidate(courseProvider);
}
