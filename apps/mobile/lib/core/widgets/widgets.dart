import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';

/// Rounded progress bar used for XP, daily goals and course progress.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({super.key, required this.value, this.color, this.height = 10});
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      value: '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.pill),
        child: Container(
          height: height,
          color: scheme.outline.withValues(alpha: 0.5),
          alignment: Alignment.centerLeft,
          child: AnimatedFractionallySizedBox(
            duration: Motion.normal,
            curve: Motion.curve,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(color: color ?? scheme.primary, borderRadius: BorderRadius.circular(Radii.pill)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact icon + value pill (XP, streak, level).
class StatPill extends StatelessWidget {
  const StatPill({super.key, required this.icon, required this.label, required this.color, this.semanticLabel});
  final IconData icon;
  final String label;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(Radii.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Space.xs),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.xl, bottom: Space.md),
      child: Row(children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Renders an [AsyncValue] with consistent loading and retryable error states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, required this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => ErrorState(message: err.toString(), onRetry: onRetry),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: Space.md),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: Space.lg),
          OutlinedButton(onPressed: onRetry, child: const Text('Tekrar dene')),
        ]),
      ),
    );
  }
}

IconData categoryIcon(String name) => switch (name) {
      'translate' => Icons.translate_rounded,
      'code' => Icons.code_rounded,
      'functions' => Icons.functions_rounded,
      'science' => Icons.science_rounded,
      _ => Icons.school_rounded,
    };

String levelLabel(String level) => switch (level) {
      'BEGINNER' => 'Başlangıç',
      'INTERMEDIATE' => 'Orta',
      'ADVANCED' => 'İleri',
      _ => level,
    };
