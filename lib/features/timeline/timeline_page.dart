import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/models/timeline.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class TimelinePage extends ConsumerWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(timelineDaysProvider);

    return PageBody(
      children: [
        const PageTitle('Timeline', subtitle: 'Hvad du har lavet, og hvornår.'),
        async.when(
          loading: () => const Column(
            children: [
              SkeletonBox(height: 20, width: 90),
              SizedBox(height: 12),
              SkeletonBox(height: 120, radius: Insets.radius),
            ],
          ),
          error: (error, _) => InlineError(message: 'Kunne ikke hente timelinen: $error'),
          data: (days) {
            if (days.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 40),
                child: EmptyState(
                  icon: AppIcons.timeline,
                  title: 'Ingenting endnu',
                  message: 'Så snart du laver noget i appen, dukker det op her.',
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final day in days)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: _Day(day: day),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.day});
  final TimelineDay day;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(dayHeading(day.day), style: text.titleSmall),
            const Spacer(),
            if (day.totalMinutes > 0)
              Text('${day.totalMinutes} min', style: text.labelSmall),
          ],
        ),
        const SizedBox(height: 10),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final event in day.events) _EventRow(event: event),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventRow extends ConsumerWidget {
  const _EventRow({required this.event});
  final TimelineEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return Hoverable(
      onTap: () => _open(ref),
      builder: (hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: hovered ? colors.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(Insets.radiusSmall),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                clockOf(event.startedAt),
                style: text.bodyMedium!.copyWith(
                  color: colors.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 12),
              child: Icon(
                AppIcons.forTimeline(event.kind),
                size: 15,
                color: colors.textSecondary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title, style: text.bodyLarge),
                  if (event.summary != null && event.summary!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      event.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (event.subjectName != null) Tag(event.subjectName!),
            if (event.duration != null && event.duration!.inMinutes > 0) ...[
              const SizedBox(width: 8),
              Text('${event.duration!.inMinutes} min', style: text.labelSmall),
            ],
          ],
        ),
      ),
    );
  }

  /// Every row goes somewhere, or does nothing visible rather than pretending.
  void _open(WidgetRef ref) {
    final nav = ref.read(navigationProvider.notifier);
    final id = event.refId;
    if (id == null) return;

    switch (event.refTable) {
      case 'notes':
        nav.push(NoteDetailRoute(id));
      case 'quizzes':
        nav.push(QuizRunRoute(id));
      case 'conversations':
        nav.push(ChatRoute(conversationId: id));
      case 'focus_sessions':
        if (event.subjectId != null) nav.push(SubjectDetailRoute(event.subjectId!));
    }
  }
}
