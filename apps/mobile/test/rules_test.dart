import 'package:eduverse_ai/data/local/rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('levelForXp', () {
    test('matches the server thresholds', () {
      expect(levelForXp(0).level, 1);
      expect(levelForXp(49).level, 1);
      expect(levelForXp(50).level, 2);
      expect(levelForXp(150).level, 3);
      expect(levelForXp(-5).level, 1);
    });
  });

  group('streak', () {
    test('counts consecutive days and resets after a gap', () {
      var s = applyActivity(const StreakState(), '2026-10-31');
      s = applyActivity(s, '2026-11-01');
      expect(s.current, 2);
      expect(applyActivity(s, '2026-11-01'), same(s));
      s = applyActivity(s, '2026-11-04');
      expect(s.current, 1);
      expect(s.longest, 2);
    });

    test('is hidden once a day is missed', () {
      final s = applyActivity(const StreakState(), '2026-11-10');
      expect(visibleStreak(s, '2026-11-11'), 1);
      expect(visibleStreak(s, '2026-11-12'), 0);
    });
  });

  group('lessonXp', () {
    test('same values as the API', () {
      expect(lessonXp(10, 4, 4, true), 10);
      expect(lessonXp(10, 3, 4, true), 8);
      expect(lessonXp(10, 0, 4, true), 5);
      expect(lessonXp(10, 4, 4, false), 3);
      expect(lessonXp(10, 0, 0, true), 0);
    });
  });

  group('grade', () {
    test('word order tolerates spacing around brackets', () {
      final r = grade('WORD_ORDER', {'words': ['print', '(', '"Merhaba"', ')']}, {'sentence': 'print ( "Merhaba" )'},
          {'words': ['print', '(', '"Merhaba"', ')']});
      expect(r.correct, isTrue);
    });

    test('fill blank ignores case and trailing punctuation', () {
      expect(grade('FILL_BLANK', {}, {'accepted': ['evening']}, {'text': ' Evening! '}).correct, isTrue);
    });

    test('matching needs all pairs', () {
      final key = {'pairs': {'a': '1', 'b': '2'}};
      expect(grade('MATCHING', {}, key, {'pairs': {'a': '1', 'b': '2'}}).correct, isTrue);
      expect(grade('MATCHING', {}, key, {'pairs': {'a': '2', 'b': '1'}}).correct, isFalse);
    });

    test('rejects malformed answers', () {
      expect(() => grade('MULTIPLE_CHOICE', {'options': ['x']}, {'index': 0}, {'index': 5}), throwsA(isA<InvalidAnswer>()));
      expect(() => grade('TRUE_FALSE', {}, {'value': true}, {'value': 'yes'}), throwsA(isA<InvalidAnswer>()));
    });
  });
}
