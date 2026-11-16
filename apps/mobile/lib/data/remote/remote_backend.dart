import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../backend.dart';
import '../models/models.dart';

const _kAccess = 'eduverse.access';
const _kRefresh = 'eduverse.refresh';

/// HTTP implementation of [EduverseBackend]. Tokens live in the platform keystore
/// (Keychain / Android Keystore). A 401 triggers exactly one refresh attempt; concurrent
/// requests share the same refresh so a rotated token is never replayed.
class RemoteBackend implements EduverseBackend {
  RemoteBackend({required String baseUrl, FlutterSecureStorage? storage, Dio? dio})
      : _storage = storage ?? const FlutterSecureStorage(),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
              contentType: Headers.jsonContentType,
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.extra['auth'] != false) {
          final token = await _storage.read(key: _kAccess);
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (err, handler) async {
        final req = err.requestOptions;
        if (err.response?.statusCode == 401 && req.extra['auth'] != false && req.extra['retried'] != true) {
          if (await _refresh()) {
            req.extra['retried'] = true;
            final token = await _storage.read(key: _kAccess);
            req.headers['Authorization'] = 'Bearer $token';
            try {
              handler.resolve(await _dio.fetch(req));
            } on DioException catch (e) {
              handler.next(e);
            }
            return;
          }
        }
        handler.next(err);
      },
    ));
  }

  final Dio _dio;
  final FlutterSecureStorage _storage;
  Future<bool>? _refreshing;

  @override
  bool get isOffline => false;

  Future<bool> _refresh() {
    return _refreshing ??= () async {
      try {
        final refresh = await _storage.read(key: _kRefresh);
        if (refresh == null) return false;
        final res = await _dio.post<Map<String, dynamic>>('/auth/refresh',
            data: {'refreshToken': refresh}, options: Options(extra: {'auth': false}));
        await _save(Session.fromJson(res.data!));
        return true;
      } catch (_) {
        await _clear();
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<void> _save(Session s) async {
    await _storage.write(key: _kAccess, value: s.accessToken);
    await _storage.write(key: _kRefresh, value: s.refreshToken);
  }

  Future<void> _clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }

  Future<T> _call<T>(Future<Response<dynamic>> Function() run, T Function(dynamic data) parse) async {
    try {
      final res = await run();
      return parse(res.data);
    } on DioException catch (e) {
      throw _toBackendException(e);
    }
  }

  BackendException _toBackendException(DioException e) {
    final status = e.response?.statusCode;
    if (status == null) {
      return BackendException('Sunucuya ulaşılamadı. İnternet bağlantını kontrol et.');
    }
    final data = e.response?.data;
    final raw = data is Map ? data['message'] : null;
    final serverMessage = raw is List ? raw.join(', ') : raw?.toString();
    final message = switch (status) {
      401 => serverMessage == 'Email or password is incorrect' ? 'E-posta veya şifre hatalı.' : 'Oturumun sona erdi, tekrar giriş yap.',
      409 => serverMessage?.contains('email') == true ? 'Bu e-posta ile zaten bir hesap var.' : 'Bu işlem zaten yapılmış.',
      429 => 'Çok fazla deneme yaptın. Biraz bekleyip tekrar dene.',
      400 => 'Girilen bilgiler geçersiz${serverMessage != null ? ': $serverMessage' : '.'}',
      404 => 'İçerik bulunamadı ya da henüz kilitli.',
      _ => 'Beklenmeyen bir hata oluştu ($status).',
    };
    return BackendException(message, statusCode: status);
  }

  Map<String, dynamic> _m(dynamic d) => Map<String, dynamic>.from(d as Map);
  List<Map<String, dynamic>> _l(dynamic d) => (d as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Future<bool> hasSession() async => (await _storage.read(key: _kRefresh)) != null;

  @override
  Future<void> register({required String email, required String password, required String displayName}) async {
    final s = await _call(
      () => _dio.post('/auth/register',
          data: {'email': email, 'password': password, 'displayName': displayName},
          options: Options(extra: {'auth': false})),
      (d) => Session.fromJson(_m(d)),
    );
    await _save(s);
  }

  @override
  Future<void> login({required String email, required String password}) async {
    final s = await _call(
      () => _dio.post('/auth/login', data: {'email': email, 'password': password}, options: Options(extra: {'auth': false})),
      (d) => Session.fromJson(_m(d)),
    );
    await _save(s);
  }

  @override
  Future<void> logout() async {
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh != null) {
      try {
        await _dio.post('/auth/logout', data: {'refreshToken': refresh}, options: Options(extra: {'auth': false}));
      } catch (_) {
        // Logging out locally must always succeed.
      }
    }
    await _clear();
  }

  @override
  Future<Me> me() => _call(() => _dio.get('/me'), (d) => Me.fromJson(_m(d)));

  @override
  Future<void> completeOnboarding(OnboardingAnswers answers) =>
      _call(() => _dio.put('/me/onboarding', data: answers.toJson()), (_) {});

  @override
  Future<Dashboard> dashboard() => _call(() => _dio.get('/me/dashboard'), (d) => Dashboard.fromJson(_m(d)));

  @override
  Future<List<Category>> categories() =>
      _call(() => _dio.get('/categories'), (d) => _l(d).map(Category.fromJson).toList());

  @override
  Future<List<CourseSummary>> courses({String? category}) => _call(
        () => _dio.get('/courses', queryParameters: {if (category != null) 'category': category}),
        (d) => _l(d).map(CourseSummary.fromJson).toList(),
      );

  @override
  Future<CourseDetail> course(String slug) =>
      _call(() => _dio.get('/courses/${Uri.encodeComponent(slug)}'), (d) => CourseDetail.fromJson(_m(d)));

  @override
  Future<Lesson> lesson(String lessonId) =>
      _call(() => _dio.get('/lessons/${Uri.encodeComponent(lessonId)}'), (d) => Lesson.fromJson(_m(d)));

  @override
  Future<String> startAttempt(String lessonId) => _call(
        () => _dio.post('/lessons/${Uri.encodeComponent(lessonId)}/attempts'),
        (d) => _m(d)['attemptId'] as String,
      );

  @override
  Future<AnswerResult> submitAnswer(String attemptId, String questionId, Map<String, dynamic> response) => _call(
        () => _dio.post('/attempts/${Uri.encodeComponent(attemptId)}/answers',
            data: {'questionId': questionId, 'response': response}),
        (d) => AnswerResult.fromJson(_m(d)),
      );

  @override
  Future<CompletionResult> completeAttempt(String attemptId) => _call(
        () => _dio.post('/attempts/${Uri.encodeComponent(attemptId)}/complete'),
        (d) => CompletionResult.fromJson(_m(d)),
      );
}
