import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../brain/brain_service.dart';
import '../../core/time_format.dart';
import '../../domain/models/quiz.dart';
import '../../domain/models/school.dart';
import '../../domain/services/ai_client.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class QuizzesPage extends ConsumerStatefulWidget {
  const QuizzesPage({super.key});

  @override
  ConsumerState<QuizzesPage> createState() => _QuizzesPageState();
}

class _QuizzesPageState extends ConsumerState<QuizzesPage> {
  bool _working = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final quizzes = ref.watch(quizzesProvider).value;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final configured = ref.watch(aiStackProvider).isConfigured;

    return PageBody(
      children: [
        PageTitle(
          'Quiz',
          subtitle: 'Lav en quiz ud fra dine noter, et emne eller dine tidligere fejl.',
          trailing: AppButton(
            label: _working ? 'Laver …' : 'Lav quiz',
            tone: ButtonTone.primary,
            onPressed: _working || !configured ? null : () => _openBuilder(subjects),
          ),
        ),
        if (!configured)
          Panel(
            onTap: () => ref.read(navigationProvider.notifier).go(const SettingsRoute()),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Quizzer laves af AI\'en, så det kræver en API-nøgle. '
                    'Du kan stadig tage de quizzer, der allerede er lavet.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text('›', style: TextStyle(fontSize: 20, color: context.colors.textTertiary)),
              ],
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          InlineError(message: _error!),
        ],
        const SizedBox(height: 22),
        if (quizzes == null)
          const Column(
            children: [
              SkeletonBox(height: 70, radius: Insets.radius),
              SizedBox(height: 8),
              SkeletonBox(height: 70, radius: Insets.radius),
            ],
          )
        else if (quizzes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: EmptyState(
              icon: AppIcons.quiz,
              title: 'Ingen quizzer endnu',
              message: 'Lav en ud fra dine noter, så finder jeg ud af hvad du kan.',
              action: AppButton(
                label: 'Lav den første',
                tone: ButtonTone.primary,
                onPressed: configured ? () => _openBuilder(subjects) : null,
              ),
            ),
          )
        else
          for (final quiz in quizzes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _QuizCard(quiz: quiz, subjects: subjects),
            ),
      ],
    );
  }

  Future<void> _openBuilder(List<Subject> subjects) async {
    final options = await showModalBottomSheet<_QuizOptions>(
      context: context,
      backgroundColor: context.colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Insets.radiusLarge)),
      ),
      builder: (context) => _QuizBuilderSheet(subjects: subjects),
    );
    if (options == null || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final subject = subjects.where((s) => s.id == options.subjectId).firstOrNull;
      final quiz = await ref.read(brainProvider).generateQuiz(
            title: subject == null
                ? 'Quiz ${options.source.label.toLowerCase()}'
                : 'Quiz: ${subject.name}',
            subjectId: options.subjectId,
            source: options.source,
            questionCount: options.count,
            kinds: options.kinds,
          );
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) return;
      ref.read(navigationProvider.notifier).push(QuizRunRoute(quiz.id));
    } on AiFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Kunne ikke lave quizzen: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _QuizOptions {
  const _QuizOptions({
    required this.source,
    required this.subjectId,
    required this.count,
    required this.kinds,
  });

  final QuizSource source;
  final int? subjectId;
  final int count;
  final Set<QuestionKind> kinds;
}

class _QuizBuilderSheet extends StatefulWidget {
  const _QuizBuilderSheet({required this.subjects});
  final List<Subject> subjects;

  @override
  State<_QuizBuilderSheet> createState() => _QuizBuilderSheetState();
}

class _QuizBuilderSheetState extends State<_QuizBuilderSheet> {
  QuizSource _source = QuizSource.notes;
  int? _subjectId;
  int _count = 8;
  final Set<QuestionKind> _kinds = {
    QuestionKind.multipleChoice,
    QuestionKind.trueFalse,
    QuestionKind.shortAnswer,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lav quiz', style: text.headlineSmall),
            const SizedBox(height: 22),
            Text('Ud fra', style: text.labelSmall),
            const SizedBox(height: 8),
            ChoiceRow<QuizSource>(
              selected: _source,
              onSelected: (value) => setState(() => _source = value),
              options: [
                for (final source in QuizSource.values)
                  (value: source, label: source.label),
              ],
            ),
            if (widget.subjects.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Fag', style: text.labelSmall),
              const SizedBox(height: 8),
              ChoiceRow<int?>(
                selected: _subjectId,
                onSelected: (value) => setState(() => _subjectId = value),
                options: [
                  (value: null, label: 'Alle fag'),
                  for (final subject in widget.subjects)
                    (value: subject.id, label: subject.name),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Text('Antal spørgsmål', style: text.labelSmall),
            const SizedBox(height: 8),
            ChoiceRow<int>(
              selected: _count,
              onSelected: (value) => setState(() => _count = value),
              options: const [
                (value: 5, label: '5'),
                (value: 8, label: '8'),
                (value: 12, label: '12'),
                (value: 20, label: '20'),
              ],
            ),
            const SizedBox(height: 20),
            Text('Spørgsmålstyper', style: text.labelSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in QuestionKind.values)
                  _KindToggle(
                    label: kind.label,
                    selected: _kinds.contains(kind),
                    onTap: () => setState(() {
                      if (_kinds.contains(kind)) {
                        // Never let the user ask for a quiz with no types.
                        if (_kinds.length > 1) _kinds.remove(kind);
                      } else {
                        _kinds.add(kind);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            AppButton(
              label: 'Lav quizzen',
              tone: ButtonTone.primary,
              expand: true,
              onPressed: () => Navigator.pop(
                context,
                _QuizOptions(
                  source: _source,
                  subjectId: _subjectId,
                  count: _count,
                  kinds: Set.of(_kinds),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindToggle extends StatelessWidget {
  const _KindToggle({required this.label, required this.selected, required this.onTap});

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
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? colors.accentSoft : (hovered ? colors.surfaceHover : colors.surface),
          border: Border.all(color: selected ? colors.accent : colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge!.copyWith(
                color: selected ? colors.accent : colors.textSecondary,
              ),
        ),
      ),
    );
  }
}

class _QuizCard extends ConsumerWidget {
  const _QuizCard({required this.quiz, required this.subjects});

  final Quiz quiz;
  final List<Subject> subjects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final subject = subjects.where((s) => s.id == quiz.subjectId).firstOrNull;

    return Panel(
      onTap: () => ref.read(navigationProvider.notifier).push(QuizRunRoute(quiz.id)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quiz.title, style: text.titleMedium),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 12,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (subject != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SubjectDot(token: subject.colorToken),
                          const SizedBox(width: 6),
                          Text(subject.name, style: text.labelSmall),
                        ],
                      ),
                    Text(quiz.sourceLabel, style: text.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          Text(shortAgo(quiz.createdAt), style: text.bodySmall),
          const SizedBox(width: 14),
          Icon(AppIcons.forward, size: 19, color: context.colors.textTertiary),
        ],
      ),
    );
  }
}
