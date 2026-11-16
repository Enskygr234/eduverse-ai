import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionProvider).valueOrNull?.me;
    final dashboard = ref.watch(dashboardProvider);
    final offline = ref.watch(backendProvider).isOffline;
    final t = Theme.of(context).textTheme;
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(padding: const EdgeInsets.all(Space.xl), children: [
        Row(children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: AppColors.brand,
            child: Text(
              (me?.displayName.isNotEmpty ?? false) ? me!.displayName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me?.displayName ?? '', style: t.titleLarge),
              Text(me?.email ?? '', style: t.bodySmall),
            ]),
          ),
        ]),
        if (offline) ...[
          const SizedBox(height: Space.lg),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(color: AppColors.xp.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.sm)),
            child: const Row(children: [
              Icon(Icons.offline_bolt_rounded, color: AppColors.xp),
              SizedBox(width: Space.sm),
              Expanded(child: Text('Çevrimdışı sürüm: ilerlemen yalnızca bu cihazda saklanıyor.')),
            ]),
          ),
        ],
        const SectionTitle('İstatistikler'),
        dashboard.when(
          data: (d) => _Stats(d: d),
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(Space.xl), child: CircularProgressIndicator())),
          error: (e, _) => ErrorState(message: e.toString(), onRetry: () => ref.invalidate(dashboardProvider)),
        ),
        const SectionTitle('Görünüm'),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto_rounded)),
            ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode_rounded)),
            ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode_rounded)),
          ],
          selected: {themeMode},
          onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).state = s.first,
        ),
        const SizedBox(height: Space.xxl),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Çıkış yap'),
          onPressed: () => ref.read(sessionProvider.notifier).logout(),
        ),
      ]),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.d});
  final Dashboard d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget tile(IconData icon, String value, String label, Color color) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: color),
                const SizedBox(height: Space.sm),
                Text(value, style: t.titleLarge),
                Text(label, style: t.bodySmall),
              ]),
            ),
          ),
        );
    return Column(children: [
      Row(children: [
        tile(Icons.bolt_rounded, '${d.totalXp}', 'Toplam XP', AppColors.xp),
        const SizedBox(width: Space.md),
        tile(Icons.military_tech_rounded, '${d.level.level}', 'Seviye', AppColors.brand),
      ]),
      const SizedBox(height: Space.md),
      Row(children: [
        tile(Icons.local_fire_department_rounded, '${d.streak}', 'Güncel seri', AppColors.streak),
        const SizedBox(width: Space.md),
        tile(Icons.workspace_premium_rounded, '${d.longestStreak}', 'En uzun seri', AppColors.success),
      ]),
      const SizedBox(height: Space.lg),
      Text('Sonraki seviyeye ${d.level.nextLevelXp - d.level.currentLevelXp} XP', style: t.bodySmall),
      const SizedBox(height: Space.sm),
      AppProgressBar(value: d.level.progress, color: AppColors.brand),
    ]);
  }
}
