import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../backend.dart';
import '../models/models.dart';
import 'rules.dart';

/// Minimal key-value persistence so the offline backend can be tested without plugins.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class MemoryStore implements KeyValueStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

const _stateKey = 'eduverse.offline.v1';

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

/// Offline implementation of [EduverseBackend]: the bundled course pack plus
/// on-device accounts and progress. It mirrors the API's rules (locking, grading,
/// one answer per question, XP once per attempt) so behaviour matches online mode.
class LocalBackend implements EduverseBackend {
  LocalBackend({required this.store, required this.loadContent, DateTime Function()? clock, Random? random})
      : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  final KeyValueStore store;
  final Future<String> Function() loadContent;
  final DateTime Function() _clock;
  final Random _random;

  Map<String, dynamic>? _pack;
  Map<String, dynamic>? _state;

  @override
  bool get isOffline => true;

  // ---------- persistence ----------

  Future<Map<String, dynamic>> _content() async => _pack ??= jsonDecode(await loadContent()) as Map<String, dynamic>;

  Future<Map<String, dynamic>> _db() async {
    if (_state != null) return _state!;
    final raw = await store.read(_stateKey);
    _state = raw == null
        ? <String, dynamic>{'users': <String, dynamic>{}, 'attempts': <String, dynamic>{}, 'current': null}
        : jsonDecode(raw) as Map<String, dynamic>;
    return _state!;
  }

  Future<void> _flush() async => store.write(_stateKey, jsonEncode(_state));

  String _id() => List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  String _hash(String password, String salt) {
    var digest = utf8.encode('$salt:$password');
    final key = utf8.encode(salt);
    for (var i = 0; i < 5000; i++) {
      digest = Hmac(sha256, key).convert(digest).bytes;
    }
    return base64Encode(digest);
  }

  Future<Map<String, dynamic>> _user() async {
    final db = await _db();
    final email = db['current'] as String?;
    final user = email == null ? null : (db['users'] as Map<String, dynamic>)[email];
    if (user == null) throw BackendException('Oturumun sona erdi, tekrar giriş yap.', statusCode: 401);
    return user as Map<String, dynamic>;
  }

  // ---------- content helpers ----------

  Iterable<Map<String, dynamic>> _courses(Map<String, dynamic> pack) =>
      (pack['courses'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> _lessonsOf(Map<String, dynamic> course) => [
        for (final u in (course['units'] as List).cast<Map<String, dynamic>>())
          ...(u['lessons'] as List).cast<Map<String, dynamic>>(),
      ];

  Category _category(Map<String, dynamic> pack, String slug) {
    final c = (pack['categories'] as List).cast<Map<String, dynamic>>().firstWhere((c) => c['slug'] == slug);
    return Category.fromJson(c);
  }

  Map<String, dynamic> _progress(Map<String, dynamic> user) =>
      (user['progress'] as Map<String, dynamic>?) ?? (user['progress'] = <String, dynamic>{});

  CourseSummary _summary(Map<String, dynamic> pack, Map<String, dynamic> course, Map<String, dynamic> user) {
    final lessons = _lessonsOf(course);
    final progress = _progress(user);
    return CourseSummary(
      slug: course['slug'] as String,
      title: course['title'] as String,
      description: course['description'] as String,
      level: course['level'] as String,
      category: _category(pack, course['categorySlug'] as String),
      lessonCount: lessons.length,
      completedLessons: lessons.where((l) => progress.containsKey(l['slug'])).length,
    );
  }

  CourseDetail _detail(Map<String, dynamic> pack, Map<String, dynamic> course, Map<String, dynamic> user) {
    final progress = _progress(user);
    var previousCompleted = true;
    final units = <UnitNode>[];
    for (final u in (course['units'] as List).cast<Map<String, dynamic>>()) {
      final nodes = <LessonNode>[];
      for (final l in (u['lessons'] as List).cast<Map<String, dynamic>>()) {
        final completed = progress.containsKey(l['slug']);
        nodes.add(LessonNode(
          id: l['slug'] as String,
          title: l['title'] as String,
          xpReward: (l['xpReward'] as num).toInt(),
          completed: completed,
          locked: !previousCompleted,
        ));
        previousCompleted = completed;
      }
      units.add(UnitNode(title: u['title'] as String, lessons: nodes));
    }
    return CourseDetail(summary: _summary(pack, course, user), units: units);
  }

  Future<(Map<String, dynamic>, Map<String, dynamic>)> _findLesson(String lessonId) async {
    final pack = await _content();
    for (final course in _courses(pack)) {
      for (final l in _lessonsOf(course)) {
        if (l['slug'] == lessonId) return (course, l);
      }
    }
    throw BackendException('İçerik bulunamadı ya da henüz kilitli.', statusCode: 404);
  }

  Future<void> _assertUnlocked(Map<String, dynamic> course, String lessonId) async {
    final detail = _detail(await _content(), course, await _user());
    final node = detail.units.expand((u) => u.lessons).firstWhere((l) => l.id == lessonId);
    if (node.locked) throw BackendException('İçerik bulunamadı ya da henüz kilitli.', statusCode: 404);
  }

  // ---------- auth ----------

  @override
  Future<bool> hasSession() async => (await _db())['current'] != null;

  @override
  Future<void> register({required String email, required String password, required String displayName}) async {
    final db = await _db();
    final key = email.trim().toLowerCase();
    final users = db['users'] as Map<String, dynamic>;
    if (users.containsKey(key)) throw BackendException('Bu e-posta ile zaten bir hesap var.', statusCode: 409);
    final salt = _id();
    users[key] = <String, dynamic>{
      'id': _id(),
      'email': key,
      'salt': salt,
      'hash': _hash(password, salt),
      'displayName': displayName.trim(),
      'dailyGoalXp': 20,
      'interests': <String>[],
      'onboardingCompleted': false,
      'totalXp': 0,
      'progress': <String, dynamic>{},
      'xp': <dynamic>[],
      'streak': const StreakState().toJson(),
      'activity': <String, dynamic>{},
      'recommended': <String>[],
    };
    db['current'] = key;
    await _flush();
  }

  @override
  Future<void> login({required String email, required String password}) async {
    final db = await _db();
    final key = email.trim().toLowerCase();
    final user = (db['users'] as Map<String, dynamic>)[key] as Map<String, dynamic>?;
    if (user == null || _hash(password, user['salt'] as String) != user['hash']) {
      throw BackendException('E-posta veya şifre hatalı.', statusCode: 401);
    }
    db['current'] = key;
    await _flush();
  }

  @override
  Future<void> logout() async {
    final db = await _db();
    db['current'] = null;
    await _flush();
  }

  // ---------- profile ----------

  @override
  Future<Me> me() async {
    final u = await _user();
    return Me(
      id: u['id'] as String,
      email: u['email'] as String,
      emailVerified: false,
      displayName: u['displayName'] as String,
      dailyGoalXp: (u['dailyGoalXp'] as num).toInt(),
      interests: (u['interests'] as List).cast<String>(),
      onboardingCompleted: u['onboardingCompleted'] == true,
      totalXp: (u['totalXp'] as num).toInt(),
    );
  }

  @override
  Future<void> completeOnboarding(OnboardingAnswers answers) async {
    final pack = await _content();
    final u = await _user();
    final known = (pack['categories'] as List).map((c) => (c as Map)['slug']).toSet();
    final interests = answers.interests.where(known.contains).toList();
    if (interests.isEmpty) throw BackendException('En az bir ilgi alanı seç.', statusCode: 400);
    u['interests'] = interests;
    u['learningGoal'] = answers.learningGoal;
    u['level'] = answers.level;
    u['dailyGoalXp'] = answers.dailyGoalXp;
    u['onboardingCompleted'] = true;
    u['recommended'] = _courses(pack).where((c) => interests.contains(c['categorySlug'])).map((c) => c['slug']).take(5).toList();
    await _flush();
  }

  @override
  Future<Dashboard> dashboard() async {
    final pack = await _content();
    final u = await _user();
    final today = isoDate(_clock());
    final streak = StreakState.fromJson(u['streak'] as Map<String, dynamic>?);
    final todayXp = (u['xp'] as List)
        .cast<Map<String, dynamic>>()
        .where((x) => x['date'] == today)
        .fold<int>(0, (sum, x) => sum + (x['amount'] as num).toInt());
    final total = (u['totalXp'] as num).toInt();
    final lvl = levelForXp(total);

    final activity = (u['activity'] as Map<String, dynamic>?) ?? {};
    final recommended = (u['recommended'] as List?)?.cast<String>() ?? const <String>[];
    final ordered = activity.keys.toList()..sort((a, b) => (activity[b] as num).compareTo(activity[a] as num));
    ContinueLearning? cont;
    for (final slug in [...ordered, ...recommended]) {
      final course = _courses(pack).firstWhereOrNull((c) => c['slug'] == slug);
      if (course == null) continue;
      final d = _detail(pack, course, u);
      final next = d.units.expand((x) => x.lessons).firstWhereOrNull((l) => !l.completed && !l.locked);
      if (next == null) continue;
      cont = ContinueLearning(
        courseSlug: d.summary.slug,
        courseTitle: d.summary.title,
        completedLessons: d.summary.completedLessons,
        lessonCount: d.summary.lessonCount,
        lessonId: next.id,
        lessonTitle: next.title,
      );
      break;
    }

    final summaries = _courses(pack).map((c) => _summary(pack, c, u)).where((c) => c.completedLessons < c.lessonCount).toList()
      ..sort((a, b) => (recommended.contains(b.slug) ? 1 : 0) - (recommended.contains(a.slug) ? 1 : 0));

    return Dashboard(
      displayName: u['displayName'] as String,
      totalXp: total,
      level: LevelInfo(level: lvl.level, currentLevelXp: lvl.currentLevelXp, nextLevelXp: lvl.nextLevelXp),
      todayXp: todayXp,
      dailyGoalXp: (u['dailyGoalXp'] as num).toInt(),
      streak: visibleStreak(streak, today),
      longestStreak: streak.longest,
      activeToday: streak.lastActive == today,
      continueLearning: cont,
      recommended: summaries.take(4).toList(),
    );
  }

  // ---------- catalog ----------

  @override
  Future<List<Category>> categories() async =>
      ((await _content())['categories'] as List).cast<Map<String, dynamic>>().map(Category.fromJson).toList();

  @override
  Future<List<CourseSummary>> courses({String? category}) async {
    final pack = await _content();
    final u = await _user();
    return _courses(pack)
        .where((c) => category == null || c['categorySlug'] == category)
        .map((c) => _summary(pack, c, u))
        .toList();
  }

  @override
  Future<CourseDetail> course(String slug) async {
    final pack = await _content();
    final course = _courses(pack).firstWhereOrNull((c) => c['slug'] == slug);
    if (course == null) throw BackendException('İçerik bulunamadı ya da henüz kilitli.', statusCode: 404);
    return _detail(pack, course, await _user());
  }

  // ---------- lessons ----------

  @override
  Future<Lesson> lesson(String lessonId) async {
    final (course, l) = await _findLesson(lessonId);
    await _assertUnlocked(course, lessonId);
    final questions = (l['questions'] as List).cast<Map<String, dynamic>>();
    return Lesson(
      id: lessonId,
      title: l['title'] as String,
      explanation: l['explanation'] as String,
      examples: (l['examples'] as List).cast<String>(),
      xpReward: (l['xpReward'] as num).toInt(),
      courseTitle: course['title'] as String,
      questions: [
        for (var i = 0; i < questions.length; i++)
          Question(
            id: '$lessonId#$i',
            type: parseQuestionType(questions[i]['type'] as String),
            prompt: questions[i]['prompt'] as String,
            payload: Map<String, dynamic>.from(questions[i]['payload'] as Map),
          ),
      ],
    );
  }

  @override
  Future<String> startAttempt(String lessonId) async {
    final (course, _) = await _findLesson(lessonId);
    await _assertUnlocked(course, lessonId);
    final u = await _user();
    final id = _id();
    (await _db())['attempts'][id] = <String, dynamic>{
      'user': u['email'],
      'lesson': lessonId,
      'answers': <String, dynamic>{},
      'status': 'IN_PROGRESS',
    };
    await _flush();
    return id;
  }

  Future<Map<String, dynamic>> _attempt(String attemptId) async {
    final u = await _user();
    final a = ((await _db())['attempts'] as Map<String, dynamic>)[attemptId] as Map<String, dynamic>?;
    if (a == null || a['user'] != u['email']) throw BackendException('İçerik bulunamadı.', statusCode: 404);
    return a;
  }

  @override
  Future<AnswerResult> submitAnswer(String attemptId, String questionId, Map<String, dynamic> response) async {
    final a = await _attempt(attemptId);
    if (a['status'] != 'IN_PROGRESS') throw BackendException('Bu işlem zaten yapılmış.', statusCode: 409);
    final (_, l) = await _findLesson(a['lesson'] as String);
    final prefix = '${a['lesson']}#';
    final index = questionId.startsWith(prefix) ? int.tryParse(questionId.substring(prefix.length)) : null;
    final questions = (l['questions'] as List).cast<Map<String, dynamic>>();
    if (index == null || index < 0 || index >= questions.length) {
      throw BackendException('İçerik bulunamadı.', statusCode: 404);
    }
    final answers = a['answers'] as Map<String, dynamic>;
    if (answers.containsKey(questionId)) throw BackendException('Bu işlem zaten yapılmış.', statusCode: 409);

    final q = questions[index];
    final result = _grade(q, response);
    answers[questionId] = result.correct;
    await _flush();
    return AnswerResult(correct: result.correct, correctAnswer: result.correctAnswer, explanation: q['explanation'] as String);
  }

  GradeResult _grade(Map<String, dynamic> q, Map<String, dynamic> response) {
    try {
      return grade(q['type'] as String, Map<String, dynamic>.from(q['payload'] as Map),
          Map<String, dynamic>.from(q['answerKey'] as Map), response);
    } on InvalidAnswer {
      throw BackendException('Girilen cevap geçersiz.', statusCode: 400);
    }
  }

  @override
  Future<CompletionResult> completeAttempt(String attemptId) async {
    final a = await _attempt(attemptId);
    if (a['status'] != 'IN_PROGRESS') throw BackendException('Bu işlem zaten yapılmış.', statusCode: 409);
    final (course, l) = await _findLesson(a['lesson'] as String);
    final total = (l['questions'] as List).length;
    final answers = (a['answers'] as Map<String, dynamic>).values.cast<bool>().toList();
    if (answers.length < total) throw BackendException('Önce tüm soruları cevapla.', statusCode: 400);

    final u = await _user();
    final correct = answers.where((c) => c).length;
    final accuracy = (correct * 100 / total).round();
    final progress = _progress(u);
    final lessonId = a['lesson'] as String;
    final first = !progress.containsKey(lessonId);
    final prev = progress[lessonId] as Map<String, dynamic>?;
    progress[lessonId] = {
      'times': ((prev?['times'] as num?)?.toInt() ?? 0) + 1,
      'best': max(accuracy, (prev?['best'] as num?)?.toInt() ?? 0),
    };

    final now = _clock();
    final today = isoDate(now);
    final xp = lessonXp((l['xpReward'] as num).toInt(), correct, total, first);
    (u['xp'] as List).add({'amount': xp, 'date': today, 'attempt': attemptId});
    u['totalXp'] = (u['totalXp'] as num).toInt() + xp;
    final streak = applyActivity(StreakState.fromJson(u['streak'] as Map<String, dynamic>?), today);
    u['streak'] = streak.toJson();
    ((u['activity'] as Map<String, dynamic>?) ?? (u['activity'] = <String, dynamic>{}))[course['slug'] as String] =
        now.millisecondsSinceEpoch;
    a['status'] = 'COMPLETED';
    await _flush();

    final lvl = levelForXp(u['totalXp'] as int);
    return CompletionResult(
      xpAwarded: xp,
      correctCount: correct,
      totalCount: total,
      accuracy: accuracy,
      streak: streak.current,
      totalXp: u['totalXp'] as int,
      firstCompletion: first,
      level: LevelInfo(level: lvl.level, currentLevelXp: lvl.currentLevelXp, nextLevelXp: lvl.nextLevelXp),
    );
  }
}
