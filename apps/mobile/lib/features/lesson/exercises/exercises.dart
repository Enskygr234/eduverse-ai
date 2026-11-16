import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../data/models/models.dart';

/// Called with the answer payload the API expects, or null while the answer is incomplete.
typedef ResponseChanged = void Function(Map<String, dynamic>? response);

/// Picks the right exercise widget for a question type.
Widget buildExercise(Question q, {required bool locked, required ResponseChanged onChanged}) {
  final key = ValueKey(q.id);
  return switch (q.type) {
    QuestionType.multipleChoice => MultipleChoiceExercise(key: key, question: q, locked: locked, onChanged: onChanged),
    QuestionType.trueFalse => TrueFalseExercise(key: key, locked: locked, onChanged: onChanged),
    QuestionType.fillBlank => FillBlankExercise(key: key, question: q, locked: locked, onChanged: onChanged),
    QuestionType.wordOrder => WordOrderExercise(key: key, question: q, locked: locked, onChanged: onChanged),
    QuestionType.matching => MatchingExercise(key: key, question: q, locked: locked, onChanged: onChanged),
    QuestionType.unknown => const Text('Bu soru tipi uygulamanın bu sürümünde desteklenmiyor.'),
  };
}

/// Human-readable correct answer for the feedback panel.
String describeCorrectAnswer(Question q, Map<String, dynamic> answer) {
  switch (q.type) {
    case QuestionType.multipleChoice:
      final options = q.strings('options');
      final i = answer['index'];
      return i is int && i >= 0 && i < options.length ? options[i] : '';
    case QuestionType.trueFalse:
      return answer['value'] == true ? 'Doğru' : 'Yanlış';
    case QuestionType.fillBlank:
      return '${answer['text'] ?? ''}';
    case QuestionType.wordOrder:
      return '${answer['sentence'] ?? ''}';
    case QuestionType.matching:
      final pairs = answer['pairs'];
      return pairs is Map ? pairs.entries.map((e) => '${e.key} → ${e.value}').join('\n') : '';
    case QuestionType.unknown:
      return '';
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.label, required this.selected, required this.onTap, this.leading});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;

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
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.1) : scheme.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: selected ? scheme.primary : scheme.outline, width: 2),
          ),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: Space.md)],
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
          ]),
        ),
      ),
    );
  }
}

class MultipleChoiceExercise extends StatefulWidget {
  const MultipleChoiceExercise({super.key, required this.question, required this.locked, required this.onChanged});
  final Question question;
  final bool locked;
  final ResponseChanged onChanged;

  @override
  State<MultipleChoiceExercise> createState() => _MultipleChoiceExerciseState();
}

class _MultipleChoiceExerciseState extends State<MultipleChoiceExercise> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final options = widget.question.strings('options');
    return Column(children: [
      for (var i = 0; i < options.length; i++) ...[
        _ChoiceTile(
          label: options[i],
          selected: _selected == i,
          leading: CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
          onTap: widget.locked
              ? null
              : () {
                  setState(() => _selected = i);
                  widget.onChanged({'index': i});
                },
        ),
        const SizedBox(height: Space.md),
      ],
    ]);
  }
}

class TrueFalseExercise extends StatefulWidget {
  const TrueFalseExercise({super.key, required this.locked, required this.onChanged});
  final bool locked;
  final ResponseChanged onChanged;

  @override
  State<TrueFalseExercise> createState() => _TrueFalseExerciseState();
}

class _TrueFalseExerciseState extends State<TrueFalseExercise> {
  bool? _value;

  @override
  Widget build(BuildContext context) {
    Widget tile(bool v, String label, IconData icon) => Expanded(
          child: _ChoiceTile(
            label: label,
            selected: _value == v,
            leading: Icon(icon),
            onTap: widget.locked
                ? null
                : () {
                    setState(() => _value = v);
                    widget.onChanged({'value': v});
                  },
          ),
        );
    return Row(children: [
      tile(true, 'Doğru', Icons.check_circle_outline_rounded),
      const SizedBox(width: Space.md),
      tile(false, 'Yanlış', Icons.highlight_off_rounded),
    ]);
  }
}

class FillBlankExercise extends StatefulWidget {
  const FillBlankExercise({super.key, required this.question, required this.locked, required this.onChanged});
  final Question question;
  final bool locked;
  final ResponseChanged onChanged;

  @override
  State<FillBlankExercise> createState() => _FillBlankExerciseState();
}

class _FillBlankExerciseState extends State<FillBlankExercise> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sentence = '${widget.question.payload['sentence'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (sentence.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          child: Text(sentence, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        ),
      TextField(
        controller: _controller,
        enabled: !widget.locked,
        autofocus: true,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(hintText: 'Cevabını yaz'),
        onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : {'text': v}),
      ),
    ]);
  }
}

class WordOrderExercise extends StatefulWidget {
  const WordOrderExercise({super.key, required this.question, required this.locked, required this.onChanged});
  final Question question;
  final bool locked;
  final ResponseChanged onChanged;

  @override
  State<WordOrderExercise> createState() => _WordOrderExerciseState();
}

class _WordOrderExerciseState extends State<WordOrderExercise> {
  /// Indices into the word bank, in the order the learner picked them.
  final List<int> _picked = [];

  void _emit(List<String> bank) =>
      widget.onChanged(_picked.isEmpty ? null : {'words': [for (final i in _picked) bank[i]]});

  @override
  Widget build(BuildContext context) {
    final bank = widget.question.strings('words');
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String text, VoidCallback? onTap, {bool ghost = false}) => Padding(
          padding: const EdgeInsets.all(Space.xs),
          child: ActionChip(
            label: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: ghost ? Colors.transparent : null)),
            onPressed: onTap,
            side: BorderSide(color: scheme.outline, width: 2),
            backgroundColor: ghost ? scheme.outline.withValues(alpha: 0.4) : scheme.surface,
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(Space.sm),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outline, width: 2), top: BorderSide(color: scheme.outline, width: 2)),
        ),
        child: Wrap(children: [
          for (var p = 0; p < _picked.length; p++)
            chip(bank[_picked[p]], widget.locked
                ? null
                : () {
                    setState(() => _picked.removeAt(p));
                    _emit(bank);
                  }),
        ]),
      ),
      const SizedBox(height: Space.xl),
      Wrap(alignment: WrapAlignment.center, children: [
        for (var i = 0; i < bank.length; i++)
          _picked.contains(i)
              ? chip(bank[i], null, ghost: true)
              : chip(bank[i], widget.locked
                  ? null
                  : () {
                      setState(() => _picked.add(i));
                      _emit(bank);
                    }),
      ]),
    ]);
  }
}

class MatchingExercise extends StatefulWidget {
  const MatchingExercise({super.key, required this.question, required this.locked, required this.onChanged});
  final Question question;
  final bool locked;
  final ResponseChanged onChanged;

  @override
  State<MatchingExercise> createState() => _MatchingExerciseState();
}

class _MatchingExerciseState extends State<MatchingExercise> {
  static const _pairColors = [Color(0xFF2F80ED), Color(0xFFF2994A), Color(0xFF27AE60), Color(0xFF9B51E0), Color(0xFFEB5757), Color(0xFF00A3A3)];
  final Map<String, String> _pairs = {};
  String? _activeLeft;

  void _tapLeft(String l) {
    final wasPaired = _pairs.containsKey(l);
    setState(() {
      _pairs.remove(l);
      _activeLeft = _activeLeft == l ? null : l;
    });
    if (wasPaired) _emit();
  }

  void _tapRight(String r) {
    if (_activeLeft == null) return;
    setState(() {
      _pairs.removeWhere((_, v) => v == r);
      _pairs[_activeLeft!] = r;
      _activeLeft = null;
    });
    _emit();
  }

  void _emit() {
    final left = widget.question.strings('left');
    widget.onChanged(_pairs.length == left.length ? {'pairs': Map<String, String>.from(_pairs)} : null);
  }

  Color? _colorFor(String left) {
    final keys = widget.question.strings('left');
    return _pairs.containsKey(left) ? _pairColors[keys.indexOf(left) % _pairColors.length] : null;
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.question.strings('left');
    final right = widget.question.strings('right');
    final scheme = Theme.of(context).colorScheme;

    Widget cell(String text, {Color? color, bool active = false, VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: InkWell(
            onTap: widget.locked ? null : onTap,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: AnimatedContainer(
              duration: Motion.fast,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color?.withValues(alpha: 0.15) ?? (active ? scheme.primary.withValues(alpha: 0.1) : scheme.surface),
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: color ?? (active ? scheme.primary : scheme.outline), width: 2),
              ),
              child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        );

    String? leftFor(String r) {
      for (final e in _pairs.entries) {
        if (e.value == r) return e.key;
      }
      return null;
    }

    return Column(children: [
      Text('Önce soldan, sonra sağdan birer kutuya dokun.', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: Space.md),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(children: [
            for (final l in left) cell(l, color: _colorFor(l), active: _activeLeft == l, onTap: () => _tapLeft(l)),
          ]),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(children: [
            for (final r in right)
              cell(r, color: leftFor(r) == null ? null : _colorFor(leftFor(r)!), onTap: () => _tapRight(r)),
          ]),
        ),
      ]),
    ]);
  }
}
