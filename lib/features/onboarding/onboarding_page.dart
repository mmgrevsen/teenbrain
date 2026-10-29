/// First run.
///
/// Six questions, one per screen, all skippable except the name. Every answer
/// becomes a memory with source `onboarding` — which is the highest-trust
/// source there is, and the reason the assistant does not have to guess on day
/// one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models/memory.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _page = PageController();
  final _name = TextEditingController();
  final _grade = TextEditingController();
  final _subject = TextEditingController();
  final _goal = TextEditingController();

  final List<String> _subjects = [];
  final Set<String> _styles = {};
  int _step = 0;
  bool _saving = false;

  static const _totalSteps = 6;

  /// Common Danish school subjects, so the usual case is four taps.
  static const _suggestedSubjects = [
    'Dansk', 'Matematik', 'Engelsk', 'Historie', 'Biologi', 'Fysik/kemi',
    'Geografi', 'Tysk', 'Fransk', 'Samfundsfag', 'Idræt', 'Musik',
  ];

  static const _learningStyles = [
    ('short', 'Korte forklaringer'),
    ('examples', 'Eksempler frem for teori'),
    ('step_by_step', 'Trin for trin'),
    ('visual', 'Billeder og diagrammer'),
    ('quiz_after', 'Quiz efter forklaringen'),
    ('why_first', 'Forstå hvorfor, før hvordan'),
  ];

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    _grade.dispose();
    _subject.dispose();
    _goal.dispose();
    super.dispose();
  }

  bool get _canAdvance => _step != 1 || _name.text.trim().isNotEmpty;

  void _next() {
    if (!_canAdvance) return;
    if (_step >= _totalSteps - 1) {
      _finish();
      return;
    }
    setState(() => _step++);
    _page.animateToPage(
      _step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
    _page.animateToPage(
      _step,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _addSubject(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    if (_subjects.any((s) => s.toLowerCase() == trimmed.toLowerCase())) return;
    setState(() => _subjects.add(trimmed));
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);

    final name = _name.text.trim();
    final grade = _grade.text.trim();
    final goal = _goal.text.trim();

    final profiles = ref.read(profileRepositoryProvider);
    final school = ref.read(schoolRepositoryProvider);
    final memories = ref.read(memoryStoreProvider);

    final profile = await profiles.create(
      displayName: name,
      gradeLevel: grade.isEmpty ? null : grade,
    );
    await profiles.update(profile.copyWith(onboardedAt: DateTime.now()));

    for (final subject in _subjects) {
      await school.createSubject(subject);
    }

    // Everything the user just said, as memory the assistant can use at once.
    Future<void> remember(MemoryKind kind, String key, String value) =>
        memories.remember(
          MemoryCandidate(kind: kind, key: key, value: value, confidence: 1),
          source: MemorySource.onboarding,
        );

    await remember(MemoryKind.fact, 'name', 'Hedder $name');
    if (grade.isNotEmpty) {
      await remember(MemoryKind.fact, 'grade_level', 'Går i $grade');
    }
    if (_subjects.isNotEmpty) {
      await remember(
        MemoryKind.fact,
        'subjects',
        'Har fagene ${_subjects.join(', ')}',
      );
    }
    if (goal.isNotEmpty) {
      await remember(MemoryKind.fact, 'goal', 'Vil gerne blive bedre til $goal');
    }
    if (_styles.isNotEmpty) {
      final labels = _learningStyles
          .where((s) => _styles.contains(s.$1))
          .map((s) => s.$2.toLowerCase())
          .join(', ');
      await remember(
        MemoryKind.preference,
        'explanation_style',
        'Foretrækker $labels',
      );
    }

    ref.read(dataRevisionProvider.notifier).bump();
    ref.invalidate(profileProvider);

    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: context.pageInset),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  _Progress(step: _step, total: _totalSteps),
                  Expanded(
                    child: PageView(
                      controller: _page,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _welcome(),
                        _nameStep(),
                        _gradeStep(),
                        _subjectsStep(),
                        _goalStep(),
                        _styleStep(),
                      ],
                    ),
                  ),
                  _Controls(
                    step: _step,
                    total: _totalSteps,
                    canAdvance: _canAdvance,
                    saving: _saving,
                    onBack: _back,
                    onNext: _next,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- steps

  Widget _welcome() {
    final text = Theme.of(context).textTheme;
    return _Step(
      children: [
        Text('TeenBrain', style: text.displaySmall),
        const SizedBox(height: 14),
        Text(
          'Jeg er en hjælper, der husker.\n\n'
          'Jo mere vi arbejder sammen, jo bedre kender jeg dine fag, hvad du er '
          'god til, og hvad der driller. Alt bliver på din egen maskine, og du '
          'kan altid se og slette det, jeg har lært.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: 20),
        Text(
          'Fire hurtige spørgsmål, så er vi i gang.',
          style: text.bodyMedium,
        ),
      ],
    );
  }

  Widget _nameStep() => _Step(
        children: [
          Text('Hvad hedder du?', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          AppTextField(
            controller: _name,
            hint: 'Dit fornavn er nok',
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _next(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          ),
        ],
      );

  Widget _gradeStep() => _Step(
        children: [
          Text('Hvilket klassetrin går du på?',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Så rammer jeg niveauet rigtigt.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          AppTextField(
            controller: _grade,
            hint: 'Fx 8. klasse eller 1.g',
            onSubmitted: (_) => _next(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          ),
        ],
      );

  Widget _subjectsStep() {
    final text = Theme.of(context).textTheme;
    return _Step(
      children: [
        Text('Hvilke fag har du?', style: text.headlineMedium),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final subject in _suggestedSubjects)
              _Pick(
                label: subject,
                selected: _subjects.contains(subject),
                onTap: () => setState(() {
                  if (_subjects.contains(subject)) {
                    _subjects.remove(subject);
                  } else {
                    _subjects.add(subject);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _subject,
                hint: 'Et andet fag …',
                onSubmitted: (value) {
                  _addSubject(value);
                  _subject.clear();
                },
              ),
            ),
            const SizedBox(width: 10),
            AppButton(
              label: 'Tilføj',
              onPressed: () {
                _addSubject(_subject.text);
                _subject.clear();
              },
            ),
          ],
        ),
        if (_subjects.any((s) => !_suggestedSubjects.contains(s))) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final subject in _subjects.where((s) => !_suggestedSubjects.contains(s)))
                _Pick(
                  label: subject,
                  selected: true,
                  onTap: () => setState(() => _subjects.remove(subject)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _goalStep() => _Step(
        children: [
          Text('Hvad vil du gerne blive bedre til?',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Et fag, et emne, eller bare "at komme i gang til tiden".',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          AppTextField(
            controller: _goal,
            hint: 'Fx andengradsligninger',
            minLines: 2,
            maxLines: 4,
            padding: const EdgeInsets.all(16),
          ),
        ],
      );

  Widget _styleStep() {
    final text = Theme.of(context).textTheme;
    return _Step(
      children: [
        Text('Hvordan lærer du bedst?', style: text.headlineMedium),
        const SizedBox(height: 8),
        Text('Vælg det, der passer. Jeg justerer mine forklaringer efter det.',
            style: text.bodyMedium),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (code, label) in _learningStyles)
              _Pick(
                label: label,
                selected: _styles.contains(code),
                onTap: () => setState(() {
                  if (_styles.contains(code)) {
                    _styles.remove(code);
                  } else {
                    _styles.add(code);
                  }
                }),
              ),
          ],
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              height: 3,
              margin: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
              decoration: BoxDecoration(
                color: i <= step ? colors.accent : colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.step,
    required this.total,
    required this.canAdvance,
    required this.saving,
    required this.onBack,
    required this.onNext,
  });

  final int step;
  final int total;
  final bool canAdvance;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isLast = step >= total - 1;
    return Row(
      children: [
        if (step > 0)
          AppButton(label: 'Tilbage', onPressed: saving ? null : onBack)
        else
          const SizedBox.shrink(),
        const Spacer(),
        AppButton(
          label: saving
              ? 'Gemmer …'
              : isLast
                  ? 'Jeg er klar'
                  : step == 0
                      ? 'Kom i gang'
                      : 'Videre',
          tone: ButtonTone.primary,
          onPressed: canAdvance && !saving ? onNext : null,
        ),
      ],
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Hoverable(
      onTap: onTap,
      builder: (hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colors.accentSoft
              : hovered
                  ? colors.surfaceHover
                  : colors.surface,
          border: Border.all(color: selected ? colors.accent : colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge!.copyWith(
                color: selected ? colors.accent : colors.textPrimary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
        ),
      ),
    );
  }
}
