import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import 'exercises/exercises.dart';

enum _Phase { loading, error, intro, question, finishing, done }

/// Plays one lesson: explanation → questions with instant server-graded feedback → results.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.lessonId});
  final String lessonId;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  _Phase _phase = _Phase.loading;
  String? _error;
  Lesson? _lesson;
  String? _attemptId;
  int _index = 0;
  Map<String, dynamic>? _response;
  AnswerResult? _feedback;
  bool _checking = false;
  int _correct = 0;
  CompletionResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _phase = _Phase.loading;
      _error = null;
    });
    final backend = ref.read(backendProvider);
    try {
      final lesson = await backend.lesson(widget.lessonId);
      final attemptId = await backend.startAttempt(widget.lessonId);
      if (!mounted) return;
      setState(() {
        _lesson = lesson;
        _attemptId = attemptId;
        _phase = _Phase.intro;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _phase = _Phase.error;
        });
      }
    }
  }

  Future<void> _check() async {
    final q = _lesson!.questions[_index];
    setState(() => _checking = true);
    try {
      final result = await ref.read(backendProvider).submitAnswer(_attemptId!, q.id, _response!);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _feedback = result;
        if (result.correct) _correct++;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _next() async {
    if (_index + 1 < _lesson!.questions.length) {
      setState(() {
        _index++;
        _response = null;
        _feedback = null;
      });
      return;
    }
    setState(() => _phase = _Phase.finishing);
    try {
      final result = await ref.read(backendProvider).completeAttempt(_attemptId!);
      if (!mounted) return;
      invalidateProgress(ref);
      setState(() {
        _result = result;
        _phase = _Phase.done;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _phase = _Phase.error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _lesson?.questions.length ?? 1;
    final progress = switch (_phase) {
      _Phase.question => (_index + (_feedback == null ? 0 : 1)) / total,
      _Phase.finishing || _Phase.done => 1.0,
      _ => 0.0,
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Dersten çık', icon: const Icon(Icons.close_rounded), onPressed: () => context.pop()),
        title: _phase == _Phase.done ? null : AppProgressBar(value: progress, color: AppColors.success),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.loading:
      case _Phase.finishing:
        return const Center(child: CircularProgressIndicator());
      case _Phase.error:
        return ErrorState(message: _error ?? 'Bir hata oluştu', onRetry: _load);
      case _Phase.intro:
        return _Intro(lesson: _lesson!, onStart: () => setState(() => _phase = _Phase.question));
      case _Phase.question:
        return _questionView();
      case _Phase.done:
        return _Results(result: _result!, onFinish: () => context.pop());
    }
  }

  Widget _questionView() {
    final q = _lesson!.questions[_index];
    final t = Theme.of(context).textTheme;
    final fb = _feedback;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(Space.xl), children: [
          Text('Soru ${_index + 1}/${_lesson!.questions.length}', style: t.bodySmall),
          const SizedBox(height: Space.sm),
          Text(q.prompt, style: t.titleLarge),
          const SizedBox(height: Space.xl),
          buildExercise(q, locked: fb != null || _checking, onChanged: (r) => setState(() => _response = r)),
        ]),
      ),
      AnimatedContainer(
        duration: Motion.normal,
        padding: const EdgeInsets.all(Space.xl),
        color: fb == null ? Colors.transparent : (fb.correct ? AppColors.successSoft : AppColors.dangerSoft),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (fb != null) ...[
            Row(children: [
              Icon(fb.correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: fb.correct ? AppColors.success : AppColors.danger),
              const SizedBox(width: Space.sm),
              Text(fb.correct ? 'Harika!' : 'Doğru cevap:',
                  style: t.titleMedium?.copyWith(color: fb.correct ? AppColors.success : AppColors.danger)),
            ]),
            if (!fb.correct) ...[
              const SizedBox(height: Space.xs),
              Text(describeCorrectAnswer(q, fb.correctAnswer),
                  style: t.bodyLarge?.copyWith(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ],
            if (fb.explanation.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text(fb.explanation, style: t.bodyMedium?.copyWith(color: const Color(0xFF3A3950))),
            ],
            const SizedBox(height: Space.lg),
          ],
          FilledButton(
            style: fb == null
                ? null
                : FilledButton.styleFrom(backgroundColor: fb.correct ? AppColors.success : AppColors.danger),
            onPressed: _checking ? null : (fb != null ? _next : (_response == null ? null : _check)),
            child: _checking
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text(fb == null ? 'Kontrol et' : 'Devam'),
          ),
        ]),
      ),
    ]);
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.lesson, required this.onStart});
  final Lesson lesson;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(Space.xl), children: [
          Text(lesson.courseTitle.toUpperCase(), style: t.labelMedium?.copyWith(letterSpacing: 1, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: Space.xs),
          Text(lesson.title, style: t.headlineMedium),
          const SizedBox(height: Space.lg),
          Text(lesson.explanation, style: t.bodyLarge),
          if (lesson.examples.isNotEmpty) ...[
            const SectionTitle('Örnekler'),
            for (final e in lesson.examples)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Row(children: [
                      const Icon(Icons.lightbulb_outline_rounded, color: AppColors.xp),
                      const SizedBox(width: Space.md),
                      Expanded(child: Text(e, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ),
              ),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: FilledButton(onPressed: onStart, child: Text('${lesson.questions.length} soruya başla · +${lesson.xpReward} XP')),
      ),
    ]);
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.result, required this.onFinish});
  final CompletionResult result;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget stat(IconData icon, String value, String label, Color color) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              child: Column(children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: Space.xs),
                Text(value, style: t.titleLarge?.copyWith(color: color)),
                Text(label, style: t.bodySmall),
              ]),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Spacer(),
        const Icon(Icons.emoji_events_rounded, size: 96, color: AppColors.xp),
        const SizedBox(height: Space.lg),
        Text(result.firstCompletion ? 'Ders tamamlandı!' : 'Tekrar tamamlandı!', textAlign: TextAlign.center, style: t.headlineMedium),
        const SizedBox(height: Space.xs),
        Text('${result.correctCount}/${result.totalCount} doğru', textAlign: TextAlign.center, style: t.bodyLarge),
        const SizedBox(height: Space.xl),
        Row(children: [
          stat(Icons.bolt_rounded, '+${result.xpAwarded}', 'XP', AppColors.xp),
          const SizedBox(width: Space.md),
          stat(Icons.track_changes_rounded, '%${result.accuracy}', 'İsabet', AppColors.success),
          const SizedBox(width: Space.md),
          stat(Icons.local_fire_department_rounded, '${result.streak}', 'Gün seri', AppColors.streak),
        ]),
        const SizedBox(height: Space.lg),
        Text('Seviye ${result.level.level} · ${result.level.currentLevelXp}/${result.level.nextLevelXp} XP',
            textAlign: TextAlign.center, style: t.bodySmall),
        const SizedBox(height: Space.sm),
        AppProgressBar(value: result.level.progress, color: AppColors.brand),
        const Spacer(),
        FilledButton(onPressed: onFinish, child: const Text('Devam et')),
      ]),
    );
  }
}
