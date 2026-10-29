/// Taking a quiz.
///
/// One question at a time, no going back once answered — the point is to find
/// out what the user knows, and a quiz you can edit your way through does not.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models/quiz.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class QuizRunPage extends ConsumerStatefulWidget {
  const QuizRunPage({super.key, required this.quizId});
  final int quizId;

  @override
  ConsumerState<QuizRunPage> createState() => _QuizRunPageState();
}

class _QuizRunPageState extends ConsumerState<QuizRunPage> {
  final _written = TextEditingController();

  Quiz? _quiz;
  bool _missing = false;
  QuizAttempt? _attempt;
  int _index = 0;
  String? _chosen;
  bool _grading = false;

  /// The verdict on the question just answered, shown before moving on.
  ({bool correct, String feedback})? _verdict;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _written.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final repository = ref.read(quizRepositoryProvider);
    final quiz = await repository.quiz(widget.quizId);
    if (!mounted) return;
    if (quiz == null) {
      setState(() => _missing = true);
      return;
    }
    final attempt = await repository.startAttempt(quiz.id);
    if (!mounted) return;
    setState(() {
      _quiz = quiz;
      _attempt = attempt;
    });
  }

  QuizQuestion? get _question {
    final quiz = _quiz;
    if (quiz == null || _index >= quiz.questions.length) return null;
    return quiz.questions[_index];
  }

  Future<void> _submit() async {
    final question = _question;
    final attempt = _attempt;
    if (question == null || attempt == null || _grading) return;

    final given = question.kind.needsAiGrading ? _written.text.trim() : (_chosen ?? '');
    if (given.isEmpty) return;

    setState(() => _grading = true);

    final graded = await ref.read(brainProvider).gradeAnswer(question: question, given: given);

    await ref.read(quizRepositoryProvider).recordAnswer(
          attemptId: attempt.id,
          questionId: question.id,
          given: given,
          correct: graded.correct,
          aiFeedback: graded.feedback.isEmpty ? null : graded.feedback,
        );

    if (!mounted) return;
    setState(() {
      _grading = false;
      _verdict = (
        correct: graded.correct,
        feedback: graded.feedback.isNotEmpty
            ? graded.feedback
            : (question.explanation ?? ''),
      );
    });
  }

  Future<void> _next() async {
    final quiz = _quiz;
    final attempt = _attempt;
    if (quiz == null || attempt == null) return;

    if (_index + 1 >= quiz.questions.length) {
      final finished = await ref.read(quizRepositoryProvider).finishAttempt(attempt.id);

      await ref.read(brainProvider).learnFromQuiz(quiz, finished);
      await ref.read(progressRepositoryProvider).logActivity(
            questions: finished.total,
            xp: finished.score * 10,
          );
      await ref.read(profileRepositoryProvider).addXp(finished.score * 10);
      await ref.read(progressRepositoryProvider).refreshAchievements();
      ref.read(dataRevisionProvider.notifier).bump();

      if (!mounted) return;
      ref.read(navigationProvider.notifier).push(
            QuizResultRoute(quizId: quiz.id, attemptId: finished.id),
          );
      return;
    }

    setState(() {
      _index++;
      _chosen = null;
      _verdict = null;
      _written.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final quiz = _quiz;
    final question = _question;
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    if (_missing) {
      return PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyState(
              icon: AppIcons.quiz,
              title: 'Quizzen findes ikke',
              message: 'Den er slettet, eller linket peger på noget der er væk.',
              action: AppButton(
                label: 'Til quizzerne',
                tone: ButtonTone.primary,
                onPressed: () =>
                    ref.read(navigationProvider.notifier).go(const QuizzesRoute()),
              ),
            ),
          ),
        ],
      );
    }

    if (quiz == null) {
      return const PageBody(
        children: [
          SkeletonBox(height: 28, width: 200),
          SizedBox(height: 24),
          SkeletonBox(height: 180, radius: Insets.radius),
        ],
      );
    }

    if (quiz.questions.isEmpty || question == null) {
      return PageBody(
        children: [
          EmptyState(
            icon: AppIcons.quiz,
            title: 'Quizzen er tom',
            message: 'Der er ingen spørgsmål i den her quiz.',
            action: AppButton(
              label: 'Tilbage',
              onPressed: () => ref.read(navigationProvider.notifier).pop(),
            ),
          ),
        ],
      );
    }

    final verdict = _verdict;

    return PageBody(
      children: [
        Row(
          children: [
            Expanded(child: Text(quiz.title, style: text.titleMedium)),
            Text('${_index + 1} af ${quiz.questions.length}', style: text.bodySmall),
          ],
        ),
        const SizedBox(height: 10),
        ProgressBar(value: (_index) / quiz.questions.length, height: 3),
        const SizedBox(height: 30),
        Tag(question.kind.label),
        const SizedBox(height: 14),
        Text(question.prompt, style: text.headlineSmall),
        const SizedBox(height: 24),

        if (question.kind.needsAiGrading)
          AppTextField(
            controller: _written,
            hint: question.kind == QuestionKind.explain
                ? 'Forklar med dine egne ord …'
                : 'Skriv dit svar …',
            minLines: question.kind == QuestionKind.explain ? 4 : 1,
            maxLines: 10,
            enabled: verdict == null,
            autofocus: true,
            padding: const EdgeInsets.all(14),
          )
        else
          Column(
            children: [
              for (final option in question.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Option(
                    label: option,
                    selected: _chosen == option,
                    state: verdict == null
                        ? _OptionState.open
                        : option == question.answer
                            ? _OptionState.correct
                            : (_chosen == option ? _OptionState.wrong : _OptionState.open),
                    onTap: verdict == null ? () => setState(() => _chosen = option) : null,
                  ),
                ),
            ],
          ),

        if (verdict != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (verdict.correct ? colors.positive : colors.danger)
                  .withValues(alpha: 0.08),
              border: Border.all(
                color: (verdict.correct ? colors.positive : colors.danger)
                    .withValues(alpha: 0.25),
              ),
              borderRadius: BorderRadius.circular(Insets.radiusSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  verdict.correct ? 'Rigtigt' : 'Forkert',
                  style: text.titleMedium!.copyWith(
                    color: verdict.correct ? colors.positive : colors.danger,
                  ),
                ),
                if (!verdict.correct && question.kind.needsAiGrading) ...[
                  const SizedBox(height: 6),
                  Text('Facit: ${question.answer}', style: text.bodyMedium),
                ],
                if (verdict.feedback.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(verdict.feedback, style: text.bodyMedium),
                ],
              ],
            ),
          ),
        ],

        const SizedBox(height: 26),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (verdict == null)
              AppButton(
                label: _grading ? 'Retter …' : 'Svar',
                tone: ButtonTone.primary,
                onPressed: _grading ? null : _submit,
              )
            else
              AppButton(
                label: _index + 1 >= quiz.questions.length ? 'Se resultatet' : 'Næste',
                tone: ButtonTone.primary,
                onPressed: _next,
              ),
            AppButton(
              label: 'Afbryd',
              onPressed: () => ref.read(navigationProvider.notifier).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

enum _OptionState { open, correct, wrong }

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.state,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (border, background) = switch (state) {
      _OptionState.correct => (colors.positive, colors.positive.withValues(alpha: 0.08)),
      _OptionState.wrong => (colors.danger, colors.danger.withValues(alpha: 0.08)),
      _OptionState.open => selected
          ? (colors.accent, colors.accentSoft)
          : (colors.border, colors.surface),
    };

    return Hoverable(
      onTap: onTap ?? () {},
      builder: (hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: hovered && onTap != null && state == _OptionState.open && !selected
              ? colors.surfaceHover
              : background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(Insets.radiusSmall),
        ),
        child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
