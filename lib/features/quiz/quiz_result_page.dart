import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models/quiz.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class QuizResultPage extends ConsumerWidget {
  const QuizResultPage({super.key, required this.quizId, required this.attemptId});

  final int quizId;
  final int attemptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quiz = ref.watch(quizProvider(quizId)).value;
    final attempt = ref.watch(quizAttemptProvider(attemptId)).value;
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final nav = ref.read(navigationProvider.notifier);

    if (quiz == null || attempt == null) {
      return const PageBody(
        children: [SkeletonBox(height: 120, radius: Insets.radius)],
      );
    }

    final wrong = attempt.answers.where((a) => !a.correct).toList();
    final tone = attempt.ratio >= 0.8
        ? colors.positive
        : attempt.ratio >= 0.5
            ? colors.warning
            : colors.danger;

    return PageBody(
      children: [
        const SizedBox(height: 10),
        Text('Du scorede ${attempt.scoreLine}', style: text.displaySmall),
        const SizedBox(height: 10),
        Text(_verdictLine(attempt), style: text.bodyLarge),
        const SizedBox(height: 22),
        ProgressBar(value: attempt.ratio, tone: tone, height: 6),
        const SizedBox(height: 34),

        if (wrong.isEmpty)
          Panel(
            accent: true,
            child: Text(
              'Alle rigtige. Jeg har noteret at du står stærkt i det her.',
              style: text.bodyLarge,
            ),
          )
        else ...[
          const SectionHeading('Det du missede'),
          for (final answer in wrong)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _WrongCard(
                question: quiz.questions.where((q) => q.id == answer.questionId).firstOrNull,
                answer: answer,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Fejlene er gemt i min hukommelse, så jeg kan tage dem op igen senere. '
            'Du kan se og slette dem under Min AI.',
            style: text.bodySmall,
          ),
        ],

        const SizedBox(height: 30),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AppButton(
              label: 'Tag den igen',
              tone: ButtonTone.primary,
              onPressed: () => nav.go(QuizRunRoute(quiz.id)),
            ),
            AppButton(label: 'Alle quizzer', onPressed: () => nav.go(const QuizzesRoute())),
            AppButton(label: 'Hjem', onPressed: () => nav.go(const HomeRoute())),
          ],
        ),
      ],
    );
  }

  /// Honest rather than encouraging. A teenager can tell the difference.
  String _verdictLine(QuizAttempt attempt) {
    if (attempt.total == 0) return '';
    if (attempt.ratio == 1) return 'Alle rigtige.';
    if (attempt.ratio >= 0.8) return 'Solidt. Der er kun småting tilbage.';
    if (attempt.ratio >= 0.5) return 'Halvvejs. Kig på dem herunder, så sidder det.';
    return 'Det her emne skal have en tur mere. Det er sådan det ser ud, første gang.';
  }
}

class _WrongCard extends StatelessWidget {
  const _WrongCard({required this.question, required this.answer});

  final QuizQuestion? question;
  final QuizAnswer answer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final q = question;
    if (q == null) return const SizedBox.shrink();

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.prompt, style: text.titleMedium),
          const SizedBox(height: 12),
          _Line(label: 'Dit svar', value: answer.given, tone: colors.danger),
          const SizedBox(height: 6),
          _Line(label: 'Rigtigt', value: q.answer, tone: colors.positive),
          if ((answer.aiFeedback ?? q.explanation ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(answer.aiFeedback ?? q.explanation!, style: text.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 74,
          child: Text(label, style: text.labelSmall!.copyWith(color: tone)),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '(intet svar)' : value,
            style: text.bodyMedium!.copyWith(color: context.colors.textPrimary),
          ),
        ),
      ],
    );
  }
}
