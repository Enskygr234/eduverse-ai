import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';

class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});

  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final courses = ref.watch(coursesProvider(_category));
    return Scaffold(
      appBar: AppBar(title: const Text('Kurslar')),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: categories.maybeWhen(
            data: (list) => ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: Space.sm),
                  child: ChoiceChip(label: const Text('Tümü'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
                ),
                for (final c in list)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.sm),
                    child: ChoiceChip(
                      avatar: Icon(categoryIcon(c.icon), size: 18),
                      label: Text(c.name),
                      selected: _category == c.slug,
                      onSelected: (_) => setState(() => _category = c.slug),
                    ),
                  ),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ),
        Expanded(
          child: AsyncView<List<CourseSummary>>(
            value: courses,
            onRetry: () => ref.invalidate(coursesProvider(_category)),
            data: (list) => list.isEmpty
                ? const Center(child: Text('Bu kategoride henüz kurs yok.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(Space.xl),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: Space.md),
                    itemBuilder: (_, i) => CourseCard(course: list[i]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class CourseCard extends StatelessWidget {
  const CourseCard({super.key, required this.course});
  final CourseSummary course;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = AppColors.fromHex(course.category.color);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/course/${Uri.encodeComponent(course.slug)}'),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(categoryIcon(course.category.icon), color: color, size: 30),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course.title, style: t.titleMedium),
                const SizedBox(height: 2),
                Text(course.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                const SizedBox(height: Space.sm),
                AppProgressBar(value: course.progress, color: color, height: 8),
                const SizedBox(height: Space.xs),
                Text('${levelLabel(course.level)} · ${course.completedLessons}/${course.lessonCount} ders', style: t.bodySmall),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
