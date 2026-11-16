import 'dart:convert';
import 'dart:io';

import 'package:eduverse_ai/data/backend.dart';
import 'package:eduverse_ai/data/local/local_backend.dart';
import 'package:eduverse_ai/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

final _packText = File('assets/content/courses.json').readAsStringSync();
final _pack = jsonDecode(_packText) as Map<String, dynamic>;

Map<String, dynamic> _correct(Map<String, dynamic> q) {
  final key = q['answerKey'] as Map<String, dynamic>;
  return switch (q['type']) {
    'MULTIPLE_CHOICE' => {'index': key['index']},
    'TRUE_FALSE' => {'value': key['value']},
    'FILL_BLANK' => {'text': (key['accepted'] as List).first},
    'WORD_ORDER' => {'words': (key['sentence'] as String).split(' ')},
    _ => {'pairs': key['pairs']},
  };
}

List<Map<String, dynamic>> _questionsOf(String lessonSlug) {
  for (final c in (_pack['courses'] as List)) {
    for (final u in (c['units'] as List)) {
      for (final l in (u['lessons'] as List)) {
        if (l['slug'] == lessonSlug) return (l['questions'] as List).cast<Map<String, dynamic>>();
      }
    }
  }
  throw StateError(lessonSlug);
}

Matcher _status(int code) => isA<BackendException>().having((e) => e.statusCode, 'statusCode', code);

void main() {
  late MemoryStore store;
  late LocalBackend backend;
  var now = DateTime(2026, 11, 16, 10);

  LocalBackend make() => LocalBackend(store: store, loadContent: () async => _packText, clock: () => now);

  Future<String> play(String lessonId) async {
    final attempt = await backend.startAttempt(lessonId);
    final lesson = await backend.lesson(lessonId);
    final raw = _questionsOf(lessonId);
    for (var i = 0; i < lesson.questions.length; i++) {
      final r = await backend.submitAnswer(attempt, lesson.questions[i].id, _correct(raw[i]));
      expect(r.correct, isTrue, reason: 'question $i');
    }
    return attempt;
  }

  setUp(() {
    store = MemoryStore();
    now = DateTime(2026, 11, 16, 10);
    backend = make();
  });

  test('register, logout and login', () async {
    expect(await backend.hasSession(), isFalse);
    await backend.register(email: 'Ece@Example.com', password: 'Sifre1234', displayName: 'Ece');
    expect((await backend.me()).email, 'ece@example.com');
    await expectLater(backend.register(email: 'ece@example.com', password: 'x', displayName: 'X'), throwsA(_status(409)));
    await backend.logout();
    await expectLater(backend.me(), throwsA(_status(401)));
    await expectLater(backend.login(email: 'ece@example.com', password: 'yanlis'), throwsA(_status(401)));
    await backend.login(email: 'ece@example.com', password: 'Sifre1234');

    // State survives an app restart.
    backend = make();
    expect(await backend.hasSession(), isTrue);
    expect((await backend.me()).displayName, 'Ece');
  });

  test('full lesson flow: locking, grading, XP once, streak', () async {
    await backend.register(email: 'a@b.co', password: 'Sifre1234', displayName: 'A');
    await backend.completeOnboarding(const OnboardingAnswers(
      interests: ['languages'], learningGoal: 'travel', level: 'BEGINNER', dailyGoalXp: 20));
    expect((await backend.me()).onboardingCompleted, isTrue);

    final course = await backend.course('english-a1');
    final lessons = course.units.expand((u) => u.lessons).toList();
    expect(lessons.first.locked, isFalse);
    expect(lessons.skip(1).every((l) => l.locked), isTrue);
    await expectLater(backend.lesson(lessons[1].id), throwsA(_status(404)));

    final attempt = await play(lessons[0].id);
    final lesson = await backend.lesson(lessons[0].id);
    await expectLater(
      backend.submitAnswer(attempt, lesson.questions[0].id, _correct(_questionsOf(lessons[0].id)[0])),
      throwsA(_status(409)),
    );
    final done = await backend.completeAttempt(attempt);
    expect(done.xpAwarded, 10);
    expect(done.streak, 1);
    await expectLater(backend.completeAttempt(attempt), throwsA(_status(409)));

    final after = await backend.course('english-a1');
    final updated = after.units.expand((u) => u.lessons).toList();
    expect(updated[0].completed, isTrue);
    expect(updated[1].locked, isFalse);

    // Practice repeat on the next day gives reduced XP and extends the streak.
    now = now.add(const Duration(days: 1));
    final again = await backend.completeAttempt(await play(lessons[0].id));
    expect(again.xpAwarded, 3);
    expect(again.streak, 2);

    final d = await backend.dashboard();
    expect(d.totalXp, 13);
    expect(d.todayXp, 3);
    expect(d.continueLearning?.lessonId, lessons[1].id);
  });

  test('cannot complete with unanswered questions', () async {
    await backend.register(email: 'c@d.co', password: 'Sifre1234', displayName: 'C');
    final first = (await backend.course('python-basics')).units.first.lessons.first;
    final attempt = await backend.startAttempt(first.id);
    await expectLater(backend.completeAttempt(attempt), throwsA(_status(400)));
  });
}
