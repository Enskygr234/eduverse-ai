// Data models mirroring the API contract (apps/api). Parsing is defensive:
// unknown or missing fields fall back to safe defaults instead of crashing.

int _int(Object? v) => v is num ? v.toInt() : 0;
String _str(Object? v) => v is String ? v : '';
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _list(Object? v) => v is List ? v : const [];

class Session {
  const Session({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;

  factory Session.fromJson(Map<String, dynamic> j) =>
      Session(accessToken: _str(j['accessToken']), refreshToken: _str(j['refreshToken']));
}

class Me {
  const Me({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.displayName,
    required this.dailyGoalXp,
    required this.interests,
    required this.onboardingCompleted,
    required this.totalXp,
  });

  final String id;
  final String email;
  final bool emailVerified;
  final String displayName;
  final int dailyGoalXp;
  final List<String> interests;
  final bool onboardingCompleted;
  final int totalXp;

  factory Me.fromJson(Map<String, dynamic> j) {
    final p = _map(j['profile']);
    return Me(
      id: _str(j['id']),
      email: _str(j['email']),
      emailVerified: j['emailVerified'] == true,
      displayName: _str(p['displayName']),
      dailyGoalXp: _int(p['dailyGoalXp']),
      interests: _list(p['interests']).whereType<String>().toList(),
      onboardingCompleted: p['onboardingCompleted'] == true,
      totalXp: _int(p['totalXp']),
    );
  }
}

class LevelInfo {
  const LevelInfo({required this.level, required this.currentLevelXp, required this.nextLevelXp});
  final int level;
  final int currentLevelXp;
  final int nextLevelXp;

  double get progress => nextLevelXp == 0 ? 0 : currentLevelXp / nextLevelXp;

  factory LevelInfo.fromJson(Map<String, dynamic> j) => LevelInfo(
        level: _int(j['level']),
        currentLevelXp: _int(j['currentLevelXp']),
        nextLevelXp: _int(j['nextLevelXp']),
      );
}

class Category {
  const Category({required this.slug, required this.name, required this.icon, required this.color});
  final String slug;
  final String name;
  final String icon;
  final String color;

  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(slug: _str(j['slug']), name: _str(j['name']), icon: _str(j['icon']), color: _str(j['color']));
}

class CourseSummary {
  const CourseSummary({
    required this.slug,
    required this.title,
    required this.description,
    required this.level,
    required this.category,
    required this.lessonCount,
    required this.completedLessons,
  });

  final String slug;
  final String title;
  final String description;
  final String level;
  final Category category;
  final int lessonCount;
  final int completedLessons;

  double get progress => lessonCount == 0 ? 0 : completedLessons / lessonCount;

  factory CourseSummary.fromJson(Map<String, dynamic> j) => CourseSummary(
        slug: _str(j['slug']),
        title: _str(j['title']),
        description: _str(j['description']),
        level: _str(j['level']),
        category: Category.fromJson(_map(j['category'])),
        lessonCount: _int(j['lessonCount']),
        completedLessons: _int(j['completedLessons']),
      );
}

class LessonNode {
  const LessonNode({
    required this.id,
    required this.title,
    required this.xpReward,
    required this.completed,
    required this.locked,
  });

  final String id;
  final String title;
  final int xpReward;
  final bool completed;
  final bool locked;

  factory LessonNode.fromJson(Map<String, dynamic> j) => LessonNode(
        id: _str(j['id']),
        title: _str(j['title']),
        xpReward: _int(j['xpReward']),
        completed: j['completed'] == true,
        locked: j['locked'] == true,
      );
}

class UnitNode {
  const UnitNode({required this.title, required this.lessons});
  final String title;
  final List<LessonNode> lessons;

  factory UnitNode.fromJson(Map<String, dynamic> j) => UnitNode(
        title: _str(j['title']),
        lessons: _list(j['lessons']).map((e) => LessonNode.fromJson(_map(e))).toList(),
      );
}

class CourseDetail {
  const CourseDetail({required this.summary, required this.units});
  final CourseSummary summary;
  final List<UnitNode> units;

  factory CourseDetail.fromJson(Map<String, dynamic> j) => CourseDetail(
        summary: CourseSummary.fromJson(j),
        units: _list(j['units']).map((e) => UnitNode.fromJson(_map(e))).toList(),
      );
}

enum QuestionType { multipleChoice, trueFalse, fillBlank, matching, wordOrder, unknown }

QuestionType parseQuestionType(String raw) => switch (raw) {
      'MULTIPLE_CHOICE' => QuestionType.multipleChoice,
      'TRUE_FALSE' => QuestionType.trueFalse,
      'FILL_BLANK' => QuestionType.fillBlank,
      'MATCHING' => QuestionType.matching,
      'WORD_ORDER' => QuestionType.wordOrder,
      _ => QuestionType.unknown,
    };

class Question {
  const Question({required this.id, required this.type, required this.prompt, required this.payload});
  final String id;
  final QuestionType type;
  final String prompt;
  final Map<String, dynamic> payload;

  List<String> strings(String key) => _list(payload[key]).map((e) => e.toString()).toList();

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        id: _str(j['id']),
        type: parseQuestionType(_str(j['type'])),
        prompt: _str(j['prompt']),
        payload: _map(j['payload']),
      );
}

class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.explanation,
    required this.examples,
    required this.xpReward,
    required this.courseTitle,
    required this.questions,
  });

  final String id;
  final String title;
  final String explanation;
  final List<String> examples;
  final int xpReward;
  final String courseTitle;
  final List<Question> questions;

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        id: _str(j['id']),
        title: _str(j['title']),
        explanation: _str(j['explanation']),
        examples: _list(j['examples']).map((e) => e.toString()).toList(),
        xpReward: _int(j['xpReward']),
        courseTitle: _str(_map(j['course'])['title']),
        questions: _list(j['questions']).map((e) => Question.fromJson(_map(e))).toList(),
      );
}

class AnswerResult {
  const AnswerResult({required this.correct, required this.correctAnswer, required this.explanation});
  final bool correct;
  final Map<String, dynamic> correctAnswer;
  final String explanation;

  factory AnswerResult.fromJson(Map<String, dynamic> j) => AnswerResult(
        correct: j['correct'] == true,
        correctAnswer: _map(j['correctAnswer']),
        explanation: _str(j['explanation']),
      );
}

class CompletionResult {
  const CompletionResult({
    required this.xpAwarded,
    required this.correctCount,
    required this.totalCount,
    required this.accuracy,
    required this.streak,
    required this.totalXp,
    required this.firstCompletion,
    required this.level,
  });

  final int xpAwarded;
  final int correctCount;
  final int totalCount;
  final int accuracy;
  final int streak;
  final int totalXp;
  final bool firstCompletion;
  final LevelInfo level;

  factory CompletionResult.fromJson(Map<String, dynamic> j) => CompletionResult(
        xpAwarded: _int(j['xpAwarded']),
        correctCount: _int(j['correctCount']),
        totalCount: _int(j['totalCount']),
        accuracy: _int(j['accuracy']),
        streak: _int(j['streak']),
        totalXp: _int(j['totalXp']),
        firstCompletion: j['firstCompletion'] == true,
        level: LevelInfo.fromJson(_map(j['level'])),
      );
}

class ContinueLearning {
  const ContinueLearning({
    required this.courseSlug,
    required this.courseTitle,
    required this.completedLessons,
    required this.lessonCount,
    required this.lessonId,
    required this.lessonTitle,
  });

  final String courseSlug;
  final String courseTitle;
  final int completedLessons;
  final int lessonCount;
  final String lessonId;
  final String lessonTitle;
}

class Dashboard {
  const Dashboard({
    required this.displayName,
    required this.totalXp,
    required this.level,
    required this.todayXp,
    required this.dailyGoalXp,
    required this.streak,
    required this.longestStreak,
    required this.activeToday,
    required this.continueLearning,
    required this.recommended,
  });

  final String displayName;
  final int totalXp;
  final LevelInfo level;
  final int todayXp;
  final int dailyGoalXp;
  final int streak;
  final int longestStreak;
  final bool activeToday;
  final ContinueLearning? continueLearning;
  final List<CourseSummary> recommended;

  double get dailyProgress => dailyGoalXp == 0 ? 0 : (todayXp / dailyGoalXp).clamp(0, 1).toDouble();

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    final s = _map(j['streak']);
    final c = j['continueLearning'];
    ContinueLearning? cont;
    if (c is Map) {
      final course = _map(c['course']);
      final lesson = _map(c['nextLesson']);
      cont = ContinueLearning(
        courseSlug: _str(course['slug']),
        courseTitle: _str(course['title']),
        completedLessons: _int(course['completedLessons']),
        lessonCount: _int(course['lessonCount']),
        lessonId: _str(lesson['id']),
        lessonTitle: _str(lesson['title']),
      );
    }
    return Dashboard(
      displayName: _str(j['displayName']),
      totalXp: _int(j['totalXp']),
      level: LevelInfo.fromJson(_map(j['level'])),
      todayXp: _int(j['todayXp']),
      dailyGoalXp: _int(j['dailyGoalXp']),
      streak: _int(s['current']),
      longestStreak: _int(s['longest']),
      activeToday: s['activeToday'] == true,
      continueLearning: cont,
      recommended: _list(j['recommended']).map((e) => CourseSummary.fromJson(_map(e))).toList(),
    );
  }
}

class OnboardingAnswers {
  const OnboardingAnswers({
    required this.interests,
    required this.learningGoal,
    required this.level,
    required this.dailyGoalXp,
  });

  final List<String> interests;
  final String learningGoal;
  final String level;
  final int dailyGoalXp;

  Map<String, dynamic> toJson() => {
        'interests': interests,
        'learningGoal': learningGoal,
        'level': level,
        'dailyGoalXp': dailyGoalXp,
      };
}
