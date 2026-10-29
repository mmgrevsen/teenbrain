/// The first thing the user sees.
///
/// A greeting, what the app thinks is worth doing now, and a box to type into.
/// Everything else on the page is secondary — the point is that opening
/// TeenBrain answers "what should I be doing?" before you ask.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../brain/schemas.dart';
import '../../core/time_format.dart';
import '../../domain/models/profile.dart';
import '../../domain/models/progress.dart';
import '../../domain/models/school.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    ref.read(navigationProvider.notifier).go(ChatRoute(initialMessage: text));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).value;
    final settings = ref.watch(settingsProvider);

    return PageBody(
      children: [
        const SizedBox(height: 16),
        _Greeting(profile: profile),
        const SizedBox(height: 26),
        _AskBox(controller: _input, onSubmit: _send),
        const SizedBox(height: 30),
        const _Suggestions(),
        const SizedBox(height: 30),
        const _Upcoming(),
        if (settings.gamificationEnabled) ...[
          const SizedBox(height: 30),
          const _WeekStrip(),
        ],
        const SizedBox(height: 30),
        const _QuickActions(),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.profile});
  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = profile?.firstName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name == null || name.isEmpty ? greeting() : '${greeting()}, $name',
          style: text.displaySmall!.copyWith(
            fontSize: context.isCompact ? 28 : 34,
          ),
        ),
        const SizedBox(height: 8),
        Text('Hvad skal vi fokusere på?', style: text.bodyLarge),
      ],
    );
  }
}

/// The big input box. Sending hands the text to a fresh conversation.
class _AskBox extends StatelessWidget {
  const _AskBox({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(Insets.radius),
        boxShadow: colors.elevation,
      ),
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Column(
        children: [
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 6,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 16),
            cursorColor: colors.accent,
            cursorWidth: 1.6,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              hintText: 'Hvad kan jeg hjælpe dig med?',
              hintStyle: Theme.of(context)
                  .textTheme
                  .bodyLarge!
                  .copyWith(color: colors.textTertiary, fontSize: 16),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(label: 'Spørg', tone: ButtonTone.primary, onPressed: onSubmit),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 3-5 things the assistant thinks are worth doing now.
class _Suggestions extends ConsumerWidget {
  const _Suggestions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ai = ref.watch(aiStackProvider);
    final async = ref.watch(suggestionsProvider);

    if (!ai.isConfigured) {
      return Panel(
        onTap: () => ref.read(navigationProvider.notifier).go(const SettingsRoute()),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Forslag kræver en API-nøgle',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Tilføj din egen nøgle under Indstillinger, så foreslår jeg '
                    'hvad du skal arbejde med.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Icon(AppIcons.forward, size: 20, color: context.colors.textTertiary),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          'Forslag',
          trailing: GestureDetector(
            onTap: () => ref.invalidate(suggestionsProvider),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Text('Opdatér', style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
        ),
        async.when(
          loading: () => const Column(
            children: [
              SkeletonBox(height: 62, radius: Insets.radius),
              SizedBox(height: 8),
              SkeletonBox(height: 62, radius: Insets.radius),
              SizedBox(height: 8),
              SkeletonBox(height: 62, radius: Insets.radius),
            ],
          ),
          error: (error, _) => InlineError(
            message: 'Kunne ikke hente forslag.',
            onRetry: () => ref.invalidate(suggestionsProvider),
          ),
          data: (suggestions) {
            if (suggestions.isEmpty) {
              return Panel(
                child: Text(
                  'Jeg har ikke nok at gå efter endnu. Skriv en note, tilføj et fag '
                  'eller stil mig et spørgsmål — så begynder jeg at lægge mærke til '
                  'hvad du arbejder med.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            return Column(
              children: [
                for (final suggestion in suggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SuggestionCard(suggestion: suggestion),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.suggestion});
  final FocusSuggestion suggestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return Panel(
      elevated: true,
      onTap: () => _act(context, ref),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.title, style: text.titleMedium),
                if (suggestion.reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(suggestion.reason, style: text.bodyMedium),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _actionLabel,
              style: text.labelSmall!.copyWith(color: colors.accent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String get _actionLabel => switch (suggestion.action) {
        SuggestionAction.startFocus => 'Start',
        SuggestionAction.makeQuiz => 'Quiz',
        SuggestionAction.openSubject => 'Åbn',
        SuggestionAction.openChat || SuggestionAction.none => 'Spørg',
      };

  /// Every card does something. Where the model named a subject the app does
  /// not have, it falls back to chat rather than doing nothing.
  Future<void> _act(BuildContext context, WidgetRef ref) async {
    final nav = ref.read(navigationProvider.notifier);
    final school = ref.read(schoolRepositoryProvider);

    Subject? subject;
    if (suggestion.subjectName != null) {
      subject = await school.subjectByName(suggestion.subjectName!);
    }

    switch (suggestion.action) {
      case SuggestionAction.startFocus:
        nav.go(FocusRoute(subjectId: subject?.id));
      case SuggestionAction.openSubject:
        if (subject != null) {
          nav.go(SubjectDetailRoute(subject.id));
        } else {
          nav.go(const SubjectsRoute());
        }
      case SuggestionAction.makeQuiz:
        nav.go(const QuizzesRoute());
      case SuggestionAction.openChat:
      case SuggestionAction.none:
        nav.go(ChatRoute(initialMessage: suggestion.title));
    }
  }
}

class _Upcoming extends ConsumerWidget {
  const _Upcoming();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upcomingAssignmentsProvider);
    final assignments = async.value ?? const <Assignment>[];
    if (assignments.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading('Deadlines'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              for (final assignment in assignments.take(4))
                _AssignmentRow(assignment: assignment, now: now, colors: colors),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssignmentRow extends ConsumerWidget {
  const _AssignmentRow({required this.assignment, required this.now, required this.colors});

  final Assignment assignment;
  final DateTime now;
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = assignment.daysUntilDue(now);
    final overdue = assignment.isOverdue(now);
    final label = switch (days) {
      null => 'Ingen dato',
      < 0 => '${-days} dage over',
      0 => 'I dag',
      1 => 'I morgen',
      _ => 'Om $days dage',
    };

    return Hoverable(
      onTap: () => ref
          .read(navigationProvider.notifier)
          .go(FocusRoute(subjectId: assignment.subjectId, assignmentId: assignment.id)),
      builder: (hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: hovered ? colors.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(Insets.radiusSmall),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                assignment.title,
                style: Theme.of(context).textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Tag(
              label,
              tone: overdue
                  ? colors.danger
                  : (days ?? 99) <= 1
                      ? colors.warning
                      : colors.textTertiary,
              filled: overdue || (days ?? 99) <= 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// Seven bars and a streak. The whole of the gamification on this page.
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(weeklyProgressProvider).value;
    if (week == null || week.totalMinutes == 0) return const SizedBox.shrink();

    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider).value;
    final level = profile?.level;
    const labels = ['M', 'T', 'O', 'T', 'F', 'L', 'S'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading('Din uge'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (level != null) ...[
                    Text('Level ${level.number}', style: text.titleMedium),
                    const SizedBox(width: 8),
                    // The level's title is the part that can give: the number
                    // and the streak both have to stay readable.
                    Flexible(
                      child: Text(
                        '— ${level.title}',
                        style: text.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (week.streak.current > 0) ...[
                    const SizedBox(width: 8),
                    Tag(week.streak.label, tone: colors.accent, filled: true),
                  ],
                ],
              ),
              if (level != null) ...[
                const SizedBox(height: 12),
                ProgressBar(value: level.progress),
                const SizedBox(height: 6),
                Text('${level.xpRemaining} XP til næste level', style: text.bodySmall),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 66,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < week.days.length; i++)
                      Expanded(
                        child: _DayBar(
                          activity: week.days[i],
                          peak: week.busiestMinutes,
                          label: labels[week.days[i].day.weekday - 1],
                          isToday: i == week.days.length - 1,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${week.totalMinutes} minutter fordelt på ${week.activeDays} '
                '${week.activeDays == 1 ? 'dag' : 'dage'}',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.activity,
    required this.peak,
    required this.label,
    required this.isToday,
  });

  final DailyActivity activity;
  final int peak;
  final String label;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // A day with any activity always draws something, so "I did a little" never
    // looks identical to "I did nothing".
    final ratio = peak == 0 ? 0.0 : activity.minutesStudied / peak;
    final height = activity.isActive ? (7 + ratio * 33) : 4.0;

    return Tooltip(
      message: activity.isActive
          ? '${activity.minutesStudied} min'
          : 'Ingen aktivitet',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Capped and centred: stretched across a seventh of a wide window,
          // a bar stops reading as a bar and starts reading as a rule.
          Center(
            child: Container(
              height: height,
              width: 22,
              decoration: BoxDecoration(
                color: activity.isActive
                    ? (isToday ? colors.accent : colors.accent.withValues(alpha: 0.4))
                    : colors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: isToday ? colors.textPrimary : colors.textTertiary,
                  fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(navigationProvider.notifier);

    final actions = <Widget>[
      AppButton(
        label: 'Start fokus', iconData: AppIcons.focus, expand: true,
        onPressed: () => nav.go(const FocusRoute()),
      ),
      AppButton(
        label: 'Lav quiz', iconData: AppIcons.quiz, expand: true,
        onPressed: () => nav.go(const QuizzesRoute()),
      ),
      AppButton(
        label: 'Ny note', iconData: AppIcons.newNote, expand: true,
        onPressed: () => nav.go(const NotesRoute()),
      ),
    ];

    // Three buttons side by side need about 420 points; a phone has 390.
    if (context.isCompact) {
      return Column(
        children: [
          for (final action in actions)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: action),
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          Expanded(child: actions[i]),
          if (i != actions.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}
