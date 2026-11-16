import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../courses/courses_screen.dart';

String _greeting(DateTime now) {
  final h = now.hour;
  if (h < 6) return 'İyi geceler';
  if (h < 12) return 'Günaydın';
  if (h < 18) return 'İyi günler';
  return 'İyi akşamlar';
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    return Scaffold(
      body: SafeArea(
        child: AsyncView<Dashboard>(
          value: dashboard,
          onRetry: () => ref.invalidate(dashboardProvider),
          data: (d) => RefreshIndicator(
            onRefresh: () => ref.refresh(dashboardProvider.future),
            child: ListView(padding: const EdgeInsets.all(Space.xl), children: [
              _Header(d: d),
              const SizedBox(height: Space.xl),
              _DailyGoalCard(d: d),
              if (d.continueLearning != null) ...[
                const SectionTitle('Kaldığın yerden devam et'),
                _ContinueCard(c: d.continueLearning!),
              ],
              if (d.recommended.isNotEmpty) ...[
                const SectionTitle('Senin için önerilenler'),
                for (final c in d.recommended) ...[
                  CourseCard(course: c),
                  const SizedBox(height: Space.md),
                ],
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.d});
  final Dashboard d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        StatPill(
          icon: Icons.local_fire_department_rounded,
          label: '${d.streak}',
          color: d.activeToday ? AppColors.streak : Theme.of(context).colorScheme.onSurfaceVariant,
          semanticLabel: '${d.streak} günlük seri',
        ),
        const SizedBox(width: Space.sm),
        StatPill(icon: Icons.bolt_rounded, label: '${d.totalXp} XP', color: AppColors.xp, semanticLabel: 'Toplam ${d.totalXp} XP'),
        const SizedBox(width: Space.sm),
        StatPill(icon: Icons.military_tech_rounded, label: 'Sv ${d.level.level}', color: AppColors.brand, semanticLabel: 'Seviye ${d.level.level}'),
      ]),
      const SizedBox(height: Space.xl),
      Text('${_greeting(DateTime.now())}, ${d.displayName}!', style: t.headlineMedium),
      const SizedBox(height: Space.xs),
      Text(
        d.activeToday ? 'Bugün serini korudun, harika gidiyorsun.' : 'Bugün bir ders bitir, serin devam etsin.',
        style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ]);
  }
}

class _DailyGoalCard extends StatelessWidget {
  const _DailyGoalCard({required this.d});
  final Dashboard d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final done = d.todayXp >= d.dailyGoalXp;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: (done ? AppColors.success : AppColors.xp).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(done ? Icons.emoji_events_rounded : Icons.flag_rounded, color: done ? AppColors.success : AppColors.xp),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(done ? 'Günlük hedef tamam!' : 'Günlük hedef', style: t.titleMedium),
              const SizedBox(height: Space.sm),
              AppProgressBar(value: d.dailyProgress, color: done ? AppColors.success : AppColors.xp),
              const SizedBox(height: Space.xs),
              Text('${d.todayXp} / ${d.dailyGoalXp} XP', style: t.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.c});
  final ContinueLearning c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.brand, AppColors.brandDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      padding: const EdgeInsets.all(Space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.courseTitle.toUpperCase(), style: t.labelMedium?.copyWith(color: Colors.white70, letterSpacing: 1)),
        const SizedBox(height: Space.xs),
        Text(c.lessonTitle, style: t.titleLarge?.copyWith(color: Colors.white)),
        const SizedBox(height: Space.lg),
        AppProgressBar(value: c.lessonCount == 0 ? 0 : c.completedLessons / c.lessonCount, color: Colors.white),
        const SizedBox(height: Space.xs),
        Text('${c.completedLessons}/${c.lessonCount} ders', style: t.bodySmall?.copyWith(color: Colors.white70)),
        const SizedBox(height: Space.lg),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.brandDeep),
          onPressed: () => context.push('/lesson/${Uri.encodeComponent(c.lessonId)}'),
          child: const Text('Derse başla'),
        ),
      ]),
    );
  }
}
