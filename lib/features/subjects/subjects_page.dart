import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/models/school.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class SubjectsPage extends ConsumerWidget {
  const SubjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subjectSummariesProvider);

    return PageBody(
      children: [
        PageTitle(
          'Fag',
          subtitle: 'Hvad du arbejder med, og hvor du står.',
          trailing: AppButton(
            label: 'Tilføj fag',
            tone: ButtonTone.primary,
            onPressed: () => _addSubject(context, ref),
          ),
        ),
        async.when(
          loading: () => const Column(
            children: [
              SkeletonBox(height: 120, radius: Insets.radius),
              SizedBox(height: 10),
              SkeletonBox(height: 120, radius: Insets.radius),
            ],
          ),
          error: (error, _) => InlineError(message: 'Kunne ikke hente fagene: $error'),
          data: (summaries) {
            if (summaries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyState(
                  icon: AppIcons.subjects,
                  title: 'Ingen fag endnu',
                  message: 'Tilføj de fag du har, så kan jeg holde styr på dem for dig.',
                  action: AppButton(
                    label: 'Tilføj dit første fag',
                    tone: ButtonTone.primary,
                    onPressed: () => _addSubject(context, ref),
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final summary in summaries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SubjectCard(summary: summary),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  static Future<void> _addSubject(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: const Text('Nyt fag'),
        content: AppTextField(
          controller: controller,
          hint: 'Fx Matematik',
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annullér')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Tilføj'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.trim().isEmpty) return;
    await ref.read(schoolRepositoryProvider).createSubject(name.trim());
    ref.read(dataRevisionProvider.notifier).bump();
  }
}

class _SubjectCard extends ConsumerWidget {
  const _SubjectCard({required this.summary});
  final SubjectSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final tone = colors.subject(summary.subject.colorToken);

    return Panel(
      elevated: true,
      onTap: () => ref
          .read(navigationProvider.notifier)
          .push(SubjectDetailRoute(summary.subject.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SubjectDot(token: summary.subject.colorToken, size: 10),
              const SizedBox(width: 10),
              Expanded(child: Text(summary.subject.name, style: text.titleMedium)),
              if (summary.openAssignments.isNotEmpty)
                Tag(
                  '${summary.openAssignments.length} '
                  '${summary.openAssignments.length == 1 ? 'opgave' : 'opgaver'}',
                  tone: colors.warning,
                  filled: true,
                ),
            ],
          ),
          if (summary.topics.isNotEmpty) ...[
            const SizedBox(height: 14),
            _TopicLine(label: 'Aktuelt', topics: summary.current, tone: tone),
            _TopicLine(label: 'Mangler træning', topics: summary.needsWork, tone: colors.warning),
            _TopicLine(label: 'Stærk', topics: summary.strong, tone: colors.positive),
          ],
          const SizedBox(height: 14),
          // Three loose stats do not fit across a phone; they wrap to a second
          // line rather than being truncated.
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              if (summary.minutesLast7Days > 0)
                Text('${summary.minutesLast7Days} min sidste uge', style: text.bodySmall),
              if (summary.accuracy != null)
                Text(
                  '${summary.questionsCorrect}/${summary.questionsAnswered} rigtige '
                  '(${((summary.accuracy ?? 0) * 100).round()} %)',
                  style: text.bodySmall,
                ),
              if (summary.lastStudied != null)
                Text('Sidst ${whenPhrase(summary.lastStudied!)}', style: text.bodySmall)
              else
                Text('Ingen aktivitet endnu', style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopicLine extends StatelessWidget {
  const _TopicLine({required this.label, required this.topics, required this.tone});

  final String label;
  final List<Topic> topics;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    if (topics.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(label, style: text.labelSmall!.copyWith(color: tone)),
          ),
          Expanded(
            child: Text(
              topics.map((t) => t.name).join(', '),
              style: text.bodyMedium!.copyWith(color: context.colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
