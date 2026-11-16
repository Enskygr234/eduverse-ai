import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/config/app_config.dart';
import 'data/backend.dart';
import 'data/local/local_backend.dart';
import 'data/remote/remote_backend.dart';

class _PrefsStore implements KeyValueStore {
  _PrefsStore(this.prefs);
  final SharedPreferences prefs;
  @override
  Future<String?> read(String key) async => prefs.getString(key);
  @override
  Future<void> write(String key, String value) => prefs.setString(key, value).then((_) {});
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final EduverseBackend backend;
  if (AppConfig.hasApi) {
    backend = RemoteBackend(baseUrl: AppConfig.apiBaseUrl);
  } else {
    final prefs = await SharedPreferences.getInstance();
    backend = LocalBackend(
      store: _PrefsStore(prefs),
      loadContent: () => rootBundle.loadString('assets/content/courses.json'),
    );
  }

  runApp(ProviderScope(
    overrides: [backendProvider.overrideWithValue(backend)],
    child: const EduverseApp(),
  ));
}
