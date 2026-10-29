import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../brain/brain_service.dart';
import '../../core/time_format.dart';
import '../../domain/models/school.dart';
import '../../domain/services/ai_client.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class SubjectDetailPage extends ConsumerStatefulWidget {
  const SubjectDetailPage({super.key, required this.subjectId});
  final int subjectId;

  @override
  ConsumerState<SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends ConsumerState<SubjectDetailPage> {
  bool _makingQuiz = false;
  String? _error;

  Future<void> _quizFor(SubjectSummary summary, Topic? topic) async {
    setState(() {
      _makingQuiz = true;
      _error = null;
    });
    try {
      final quiz = await ref.read(brainProvider).generateQuiz(
            title: topic == null
                ? 'Quiz: ${summary.subject.name}'
                : 'Quiz: ${topic.name}',
            subjectId: summary.subject.id,
            topicId: topic?.id,
            source: QuizSource.topic,
          );
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) return;
      ref.read(navigationProvider.notifier).push(QuizRunRoute(quiz.id));
    } on AiFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Kunne ikke lave quizzen: $e');
    } finally {
      if (mounted) setState(() => _makingQuiz = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(subjectSummaryProvider(widget.subjectId));
    final summary = async.value;
    final nav = ref.read(navigationProvider.notifier);
    final configured = ref.watch(aiStackProvider).isConfigured;

    if (summary == null) {
      return const PageBody(
        children: [
          SkeletonBox(height: 34, width: 220),
          SizedBox(height: 24),
          SkeletonBox(height: 160, radius: Insets.radius),
        ],
      );
    }

    final colors = context.colors;
    final tone = colors.subject(summary.subject.colorToken);

    return PageBody(
      children: [
        Row(
          children: [
            SubjectDot(token: summary.subject.colorToken, size: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                summary.subject.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton(
              label: 'Start fokus',
              iconData: AppIcons.focus,
              onPressed: () => nav.push(FocusRoute(subjectId: summary.subject.id)),
            ),
            AppButton(
              label: _makingQuiz ? 'Laver quiz …' : 'Lav quiz',
              iconData: AppIcons.quiz,
              onPressed: _makingQuiz || !configured ? null : () => _quizFor(summary, null),
            ),
            AppButton(
              label: 'Noter',
              iconData: AppIcons.notes,
              onPressed: () => nav.push(NotesRoute(subjectId: summary.subject.id)),
            ),
          ],
        ),
        if (!configured)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Quiz kræver en API-nøgle under Indstillinger.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          InlineError(message: _error!),
        ],
        const SizedBox(height: 28),
        _Stats(summary: summary),
        const SizedBox(height: 28),
        const SectionHeading('Emner'),
        if (summary.topics.isEmpty)
          Panel(
            child: Text(
              'Der er ingen emner endnu. De dukker op af sig selv, når du laver '
              'quizzer eller fokus-sessioner i faget.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final topic in _ordered(summary.topics))
                  _TopicRow(
                    topic: topic,
                    tone: tone,
                    canQuiz: configured && !_makingQuiz,
                    onQuiz: () => _quizFor(summary, topic),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 28),
        _Assignments(subjectId: summary.subject.id),
      ],
    );
  }

  /// Weakest first — the page should open on what needs work.
  List<Topic> _ordered(List<Topic> topics) {
    final sorted = List.of(topics)..sort((a, b) => a.mastery.compareTo(b.mastery));
    return sorted;
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.summary});
  final SubjectSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final tiles = <({String label, String value})>[
      (label: 'Sidste uge', value: '${summary.minutesLast7Days} min'),
      if (summary.questionsAnswered > 0)
        (label: 'Spørgsmål', value: '${summary.questionsAnswered}'),
      if (summary.accuracy != null)
        (label: 'Rigtige', value: '${((summary.accuracy ?? 0) * 100).round()} %'),
      (
        label: 'Sidst',
        value: summary.lastStudied == null ? '—' : shortAgo(summary.lastStudied!),
      ),
    ];

    Widget card(({String label, String value}) tile) => Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tile.value, style: text.headlineSmall),
              const SizedBox(height: 3),
              Text(tile.label, style: text.labelSmall),
            ],
          ),
        );

    // Four tiles in a row need roughly 480 points. On a phone they go two-up.
    if (context.isCompact) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final tile in tiles)
            SizedBox(
              width: (MediaQuery.sizeOf(context).width - Insets.pageCompact * 2 - 10) / 2,
              child: card(tile),
            ),
        ],
      );
    }

    return Row(
      children: [
        for (final tile in tiles)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: card(tile),
            ),
          ),
      ],
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.topic,
    required this.tone,
    required this.canQuiz,
    required this.onQuiz,
  });

  final Topic topic;
  final Color tone;
  final bool canQuiz;
  final VoidCallback onQuiz;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final bandTone = switch (topic.band) {
      MasteryBand.needsWork => colors.warning,
      MasteryBand.current => tone,
      MasteryBand.strong => colors.positive,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(topic.name, style: text.bodyLarge)),
                    const SizedBox(width: 10),
                    Tag(topic.band.label, tone: bandTone),
                  ],
                ),
                const SizedBox(height: 8),
                ProgressBar(value: topic.mastery, tone: bandTone, height: 4),
              ],
            ),
          ),
          const SizedBox(width: 14),
          AppButton(label: 'Quiz', onPressed: canQuiz ? onQuiz : null),
        ],
      ),
    );
  }
}

class _Assignments extends ConsumerWidget {
  const _Assignments({required this.subjectId});
  final int subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(assignmentsProvider(subjectId)).value ?? const <Assignment>[];
    final now = DateTime.now();
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          'Opgaver',
          trailing: GestureDetector(
            onTap: () => _add(context, ref),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text('Tilføj', style: text.labelSmall),
            ),
          ),
        ),
        if (assignments.isEmpty)
          Panel(child: Text('Ingen opgaver i faget.', style: text.bodyMedium))
        else
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final assignment in assignments)
                  _AssignmentRow(assignment: assignment, now: now),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    var due = DateTime.now().add(const Duration(days: 1));

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: context.colors.surface,
          title: const Text('Ny opgave'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(controller: title, hint: 'Hvad skal laves?', autofocus: true),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('Deadline', style: Theme.of(context).textTheme.labelMedium),
                  const Spacer(),
                  AppButton(
                    label: dayHeading(due),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: due,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 730)),
                      );
                      if (picked != null) setState(() => due = picked);
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annullér')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Tilføj'),
            ),
          ],
        ),
      ),
    );

    final text = title.text.trim();
    title.dispose();
    if (saved != true || text.isEmpty) return;

    await ref.read(schoolRepositoryProvider).createAssignment(
          subjectId: subjectId,
          title: text,
          dueAt: due,
        );
    ref.read(dataRevisionProvider.notifier).bump();
  }
}

class _AssignmentRow extends ConsumerWidget {
  const _AssignmentRow({required this.assignment, required this.now});

  final Assignment assignment;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final days = assignment.daysUntilDue(now);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              await ref
                  .read(schoolRepositoryProvider)
                  .setAssignmentDone(assignment.id, !assignment.isDone);
              ref.read(dataRevisionProvider.notifier).bump();
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: assignment.isDone ? colors.positive : Colors.transparent,
                  border: Border.all(
                    color: assignment.isDone ? colors.positive : colors.borderStrong,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: assignment.isDone
                    ? const Icon(AppIcons.check, size: 13, color: Colors.white)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              assignment.title,
              style: text.bodyLarge!.copyWith(
                color: assignment.isDone ? colors.textTertiary : colors.textPrimary,
                decoration: assignment.isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (!assignment.isDone && days != null)
            Tag(
              switch (days) {
                < 0 => '${-days} dage over',
                0 => 'I dag',
                1 => 'I morgen',
                _ => 'Om $days dage',
              },
              tone: assignment.isOverdue(now)
                  ? colors.danger
                  : days <= 1
                      ? colors.warning
                      : colors.textTertiary,
              filled: assignment.isOverdue(now) || days <= 1,
            ),
        ],
      ),
    );
  }
}
