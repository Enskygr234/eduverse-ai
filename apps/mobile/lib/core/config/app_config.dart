/// Build-time configuration. Pass with:
///   flutter build apk --dart-define=API_BASE_URL=https://api.example.com
/// Without API_BASE_URL the app runs in offline mode on bundled content.
class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static bool get hasApi => apiBaseUrl.isNotEmpty;
}
