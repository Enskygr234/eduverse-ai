// Dart port of apps/api/src/modules/gamification/rules.ts and learning/grader.ts.
// Used only by the offline backend; the server stays the source of truth online.

class LevelCalc {
  const LevelCalc(this.level, this.currentLevelXp, this.nextLevelXp);
  final int level;
  final int currentLevelXp;
  final int nextLevelXp;
}

LevelCalc levelForXp(int totalXp) {
  var level = 1;
  var remaining = totalXp < 0 ? 0 : totalXp;
  var needed = 50;
  while (remaining >= needed) {
    remaining -= needed;
    level += 1;
    needed = level * 50;
  }
  return LevelCalc(level, remaining, needed);
}

String isoDate(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

int _dayNumber(String iso) => DateTime.parse('${iso}T00:00:00Z').millisecondsSinceEpoch ~/ 86400000;

class StreakState {
  const StreakState({this.current = 0, this.longest = 0, this.lastActive});
  final int current;
  final int longest;
  final String? lastActive;

  Map<String, dynamic> toJson() => {'current': current, 'longest': longest, 'lastActive': lastActive};

  factory StreakState.fromJson(Map<String, dynamic>? j) => StreakState(
        current: (j?['current'] as num?)?.toInt() ?? 0,
        longest: (j?['longest'] as num?)?.toInt() ?? 0,
        lastActive: j?['lastActive'] as String?,
      );
}

StreakState applyActivity(StreakState s, String today) {
  if (s.lastActive == today) return s;
  var current = 1;
  if (s.lastActive != null) {
    final diff = _dayNumber(today) - _dayNumber(s.lastActive!);
    if (diff < 0) return s;
    if (diff == 1) current = s.current + 1;
  }
  return StreakState(current: current, longest: current > s.longest ? current : s.longest, lastActive: today);
}

int visibleStreak(StreakState s, String today) {
  if (s.lastActive == null) return 0;
  return _dayNumber(today) - _dayNumber(s.lastActive!) <= 1 ? s.current : 0;
}

int lessonXp(int xpReward, int correct, int total, bool firstCompletion) {
  if (total <= 0) return 0;
  final accuracy = correct / total;
  final scaled = (xpReward * (accuracy < 0.5 ? 0.5 : accuracy)).round();
  if (firstCompletion) return scaled;
  final practice = (scaled / 3).round();
  return practice < 1 ? 1 : practice;
}

String normalizeText(String value) {
  // Turkish casing, same as the server's toLocaleLowerCase('tr').
  var s = value.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  s = s.replaceAllMapped(RegExp(r'\s*([()\[\]{}.,!?;:])\s*'), (m) => m.group(1)!);
  s = s.trim();
  return s.replaceAll(RegExp(r'[.!?]+$'), '');
}

class GradeResult {
  const GradeResult(this.correct, this.correctAnswer);
  final bool correct;
  final Map<String, dynamic> correctAnswer;
}

class InvalidAnswer implements Exception {
  InvalidAnswer(this.message);
  final String message;
}

GradeResult grade(String type, Map<String, dynamic> payload, Map<String, dynamic> key, Map<String, dynamic> response) {
  switch (type) {
    case 'MULTIPLE_CHOICE':
      final options = (payload['options'] as List?) ?? const [];
      final index = response['index'];
      if (index is! int || index < 0 || index >= options.length) throw InvalidAnswer('index');
      return GradeResult(index == key['index'], {'index': key['index']});
    case 'TRUE_FALSE':
      final value = response['value'];
      if (value is! bool) throw InvalidAnswer('value');
      return GradeResult(value == key['value'], {'value': key['value']});
    case 'FILL_BLANK':
      final text = response['text'];
      if (text is! String) throw InvalidAnswer('text');
      final accepted = ((key['accepted'] as List?) ?? const []).map((e) => e.toString()).toList();
      final given = normalizeText(text);
      return GradeResult(accepted.any((a) => normalizeText(a) == given), {'text': accepted.isEmpty ? '' : accepted.first});
    case 'WORD_ORDER':
      final words = response['words'];
      if (words is! List) throw InvalidAnswer('words');
      final expected = key['sentence'].toString();
      return GradeResult(
        normalizeText(words.map((e) => e.toString()).join(' ')) == normalizeText(expected),
        {'sentence': expected},
      );
    case 'MATCHING':
      final pairs = response['pairs'];
      final expected = Map<String, dynamic>.from((key['pairs'] as Map?) ?? const {});
      if (pairs is! Map) throw InvalidAnswer('pairs');
      final ok = pairs.length == expected.length && expected.entries.every((e) => pairs[e.key] == e.value);
      return GradeResult(ok, {'pairs': expected});
    default:
      throw InvalidAnswer('type');
  }
}
