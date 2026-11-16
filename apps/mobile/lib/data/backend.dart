import 'models/models.dart';

/// Error shown to the user. [message] is already user-facing Turkish text.
class BackendException implements Exception {
  BackendException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// The app talks to learning data only through this contract.
///
/// * [RemoteBackend] calls the EduVerse API (used when API_BASE_URL is set at build time).
/// * [LocalBackend] runs the same rules on-device for the offline build, so the
///   app is fully usable before a server is deployed.
abstract class EduverseBackend {
  /// True when data lives only on this device.
  bool get isOffline;

  Future<bool> hasSession();
  Future<void> register({required String email, required String password, required String displayName});
  Future<void> login({required String email, required String password});
  Future<void> logout();

  Future<Me> me();
  Future<void> completeOnboarding(OnboardingAnswers answers);
  Future<Dashboard> dashboard();

  Future<List<Category>> categories();
  Future<List<CourseSummary>> courses({String? category});
  Future<CourseDetail> course(String slug);

  Future<Lesson> lesson(String lessonId);
  Future<String> startAttempt(String lessonId);
  Future<AnswerResult> submitAnswer(String attemptId, String questionId, Map<String, dynamic> response);
  Future<CompletionResult> completeAttempt(String attemptId);
}
