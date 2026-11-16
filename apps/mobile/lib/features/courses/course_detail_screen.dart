import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';

/// Duolingo-style lesson path: completed, current and locked nodes in order.
class CourseDetailScreen extends ConsumerWidget {
  const CourseDetailScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(courseProvider(slug));
    return Scaffold(
      appBar: AppBar(title: Text(course.valueOrNull?.summary.title ?? '')),
      body: AsyncView<CourseDetail>(
        value: course,
        onRetry: () => ref.invalidate(courseProvider(slug)),
        data: (c) {
          final color = AppColors.fromHex(c.summary.category.color);
          final firstOpen = c.units.expand((u) => u.lessons).where((l) => !l.completed && !l.locked).firstOrNullSafe;
          return ListView(padding: const EdgeInsets.all(Space.xl), children: [
            Text(c.summary.description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: Space.md),
            AppProgressBar(value: c.summary.progress, color: color),
            const SizedBox(height: Space.xs),
            Text('${c.summary.completedLessons}/${c.summary.lessonCount} ders tamamlandı', style: Theme.of(context).textTheme.bodySmall),
            for (var ui = 0; ui < c.units.length; ui++) ...[
              SectionTitle('Ünite ${ui + 1} · ${c.units[ui].title}'),
              for (var li = 0; li < c.units[ui].lessons.length; li++)
                _PathNode(
                  lesson: c.units[ui].lessons[li],
                  color: color,
                  current: c.units[ui].lessons[li].id == firstOpen?.id,
                  offset: const [0.0, 0.35, 0.0, -0.35][li % 4],
                ),
            ],
          ]);
        },
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNullSafe {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

class _PathNode extends StatelessWidget {
  const _PathNode({required this.lesson, required this.color, required this.current, required this.offset});
  final LessonNode lesson;
  final Color color;
  final bool current;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = lesson.locked ? scheme.outline : (lesson.completed ? AppColors.success : color);
    final icon = lesson.locked
        ? Icons.lock_rounded
        : lesson.completed
            ? Icons.check_rounded
            : Icons.play_arrow_rounded;
    final status = lesson.locked ? 'kilitli' : (lesson.completed ? 'tamamlandı' : 'açık');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Align(
        alignment: Alignment(offset, 0),
        child: Semantics(
          button: !lesson.locked,
          label: '${lesson.title}, $status',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: lesson.locked
                ? () => ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Önce bir önceki dersi tamamla.')))
                : () => context.push('/lesson/${Uri.encodeComponent(lesson.id)}'),
            child: Column(children: [
              AnimatedContainer(
                duration: Motion.normal,
                width: current ? 84 : 72,
                height: current ? 84 : 72,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: bg.withValues(alpha: 0.45), offset: const Offset(0, 6), blurRadius: 0)],
                  border: current ? Border.all(color: AppColors.xp, width: 4) : null,
                ),
                child: Icon(icon, color: Colors.white, size: 36),
              ),
              const SizedBox(height: Space.sm),
              SizedBox(
                width: 160,
                child: Text(
                  lesson.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: lesson.locked ? scheme.onSurfaceVariant : scheme.onSurface,
                      ),
                ),
              ),
              Text('+${lesson.xpReward} XP', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      ),
    );
  }
}
