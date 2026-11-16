import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';

class _Option {
  const _Option(this.value, this.title, this.subtitle, this.icon);
  final String value;
  final String title;
  final String subtitle;
  final IconData icon;
}

const _goals = [
  _Option('career', 'Kariyerim için', 'İşte ve mülakatlarda öne çık', Icons.work_rounded),
  _Option('school', 'Okul ve sınavlar', 'Derslerine destek', Icons.school_rounded),
  _Option('travel', 'Seyahat', 'Gittiğin yerde rahat iletişim', Icons.flight_takeoff_rounded),
  _Option('hobby', 'Merak ve hobi', 'Yeni şeyler öğrenmenin keyfi', Icons.palette_rounded),
  _Option('brain_training', 'Zihin egzersizi', 'Her gün biraz düşün', Icons.psychology_rounded),
];

const _levels = [
  _Option('BEGINNER', 'Yeni başlıyorum', 'Konuyu sıfırdan öğrenmek istiyorum', Icons.spa_rounded),
  _Option('INTERMEDIATE', 'Biraz biliyorum', 'Temelleri gördüm, ilerlemek istiyorum', Icons.trending_up_rounded),
  _Option('ADVANCED', 'İyi seviyedeyim', 'Zorlayıcı içerik istiyorum', Icons.rocket_launch_rounded),
];

const _dailyGoals = [
  _Option('10', 'Rahat', 'Günde 10 XP · ~5 dk', Icons.coffee_rounded),
  _Option('20', 'Düzenli', 'Günde 20 XP · ~10 dk', Icons.directions_walk_rounded),
  _Option('30', 'Ciddi', 'Günde 30 XP · ~15 dk', Icons.directions_run_rounded),
  _Option('50', 'Yoğun', 'Günde 50 XP · ~25 dk', Icons.bolt_rounded),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final Set<String> _interests = {};
  String? _goal;
  String? _level;
  String? _daily = '20';
  bool _busy = false;

  bool get _canContinue => switch (_step) {
        0 => _interests.isNotEmpty,
        1 => _goal != null,
        2 => _level != null,
        _ => _daily != null,
      };

  Future<void> _next() async {
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).completeOnboarding(OnboardingAnswers(
            interests: _interests.toList(),
            learningGoal: _goal!,
            level: _level!,
            dailyGoalXp: int.parse(_daily!),
          ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final titles = ['Neler öğrenmek istersin?', 'Neden öğreniyorsun?', 'Şu anki seviyen ne?', 'Günlük hedefini seç'];
    return Scaffold(
      appBar: AppBar(
        leading: _step == 0 ? null : IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => setState(() => _step--)),
        title: AppProgressBar(value: (_step + 1) / 4),
      ),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.lg),
            child: Text(titles[_step], style: t.headlineMedium),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.normal,
              child: KeyedSubtree(key: ValueKey(_step), child: _body()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: FilledButton(
              onPressed: _canContinue && !_busy ? _next : null,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_step == 3 ? 'Planımı oluştur' : 'Devam'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case 0:
        final categories = ref.watch(categoriesProvider);
        return AsyncView<List<Category>>(
          value: categories,
          onRetry: () => ref.invalidate(categoriesProvider),
          data: (list) => GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.symmetric(horizontal: Space.xl),
            mainAxisSpacing: Space.md,
            crossAxisSpacing: Space.md,
            childAspectRatio: 1.25,
            children: [
              for (final c in list)
                _SelectTile(
                  selected: _interests.contains(c.slug),
                  color: AppColors.fromHex(c.color),
                  icon: categoryIcon(c.icon),
                  title: c.name,
                  onTap: () => setState(() => _interests.contains(c.slug) ? _interests.remove(c.slug) : _interests.add(c.slug)),
                ),
            ],
          ),
        );
      case 1:
        return _OptionList(options: _goals, selected: _goal, onSelect: (v) => setState(() => _goal = v));
      case 2:
        return _OptionList(options: _levels, selected: _level, onSelect: (v) => setState(() => _level = v));
      default:
        return _OptionList(options: _dailyGoals, selected: _daily, onSelect: (v) => setState(() => _daily = v));
    }
  }
}

class _SelectTile extends StatelessWidget {
  const _SelectTile({required this.selected, required this.color, required this.icon, required this.title, required this.onTap});
  final bool selected;
  final Color color;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: AnimatedContainer(
          duration: Motion.fast,
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : scheme.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: selected ? color : scheme.outline, width: 2),
          ),
          padding: const EdgeInsets.all(Space.lg),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: Space.sm),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
      ),
    );
  }
}

class _OptionList extends StatelessWidget {
  const _OptionList({required this.options, required this.selected, required this.onSelect});
  final List<_Option> options;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: Space.xl),
      itemCount: options.length,
      separatorBuilder: (_, __) => const SizedBox(height: Space.md),
      itemBuilder: (context, i) {
        final o = options[i];
        final isSelected = o.value == selected;
        return Semantics(
          selected: isSelected,
          button: true,
          child: InkWell(
            onTap: () => onSelect(o.value),
            borderRadius: BorderRadius.circular(Radii.md),
            child: AnimatedContainer(
              duration: Motion.fast,
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: isSelected ? scheme.primary.withValues(alpha: 0.1) : scheme.surface,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: isSelected ? scheme.primary : scheme.outline, width: 2),
              ),
              child: Row(children: [
                Icon(o.icon, color: scheme.primary),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.title, style: Theme.of(context).textTheme.titleMedium),
                    Text(o.subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
