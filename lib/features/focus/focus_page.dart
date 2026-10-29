/// Focus mode.
///
/// A timer, the thing being worked on, and nothing else. The chrome disappears
/// while it runs — that is the whole feature.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/models/focus.dart';
import '../../domain/models/school.dart';
import '../../domain/models/timeline.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key, this.subjectId, this.assignmentId});

  final int? subjectId;
  final int? assignmentId;

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  late int? _subjectId = widget.subjectId;
  int? _assignmentId;
  int _planned = 25;

  FocusSession? _session;
  Timer? _ticker;
  int _elapsed = 0;
  bool _paused = false;
  FocusSession? _finished;

  @override
  void initState() {
    super.initState();
    _assignmentId = widget.assignmentId;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final session = await ref.read(focusRepositoryProvider).start(
          subjectId: _subjectId,
          assignmentId: _assignmentId,
          plannedMinutes: _planned,
        );
    if (!mounted) return;
    setState(() {
      _session = session;
      _elapsed = 0;
      _paused = false;
      _finished = null;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused) return;
      setState(() => _elapsed++);
      if (_elapsed >= _planned * 60) _stop(completed: true);
    });
  }

  Future<void> _stop({required bool completed}) async {
    final session = _session;
    if (session == null) return;

    _ticker?.cancel();
    _ticker = null;

    final finished = await ref.read(focusRepositoryProvider).finish(
          session.id,
          actualSeconds: _elapsed,
          completed: completed,
        );

    final subject = _subjectId == null
        ? null
        : await ref.read(schoolRepositoryProvider).subject(_subjectId!);

    await ref.read(timelineRepositoryProvider).record(
          kind: TimelineKind.focus,
          title: subject == null ? 'Fokus' : 'Fokus: ${subject.name}',
          summary: finished.durationLine,
          subjectId: _subjectId,
          refTable: 'focus_sessions',
          refId: finished.id,
          startedAt: finished.startedAt,
          endedAt: finished.endedAt,
        );

    // XP tracks minutes, so a two-minute session is not worth the same as
    // half an hour.
    final minutes = finished.actualSeconds ~/ 60;
    if (minutes > 0) {
      await ref.read(progressRepositoryProvider).logActivity(minutes: minutes, xp: minutes);
      await ref.read(profileRepositoryProvider).addXp(minutes);
    }
    await ref.read(progressRepositoryProvider).refreshAchievements();
    ref.read(dataRevisionProvider.notifier).bump();

    if (!mounted) return;
    setState(() {
      _session = null;
      _finished = finished;
    });
  }

  // The sub-views describe intent; the state owns how it changes.
  void setPlanned(int minutes) => setState(() => _planned = minutes);

  void setSubject(int? id) => setState(() {
        _subjectId = id;
        _assignmentId = null;
      });

  void setAssignment(int? id) => setState(() => _assignmentId = id);

  void togglePause() => setState(() => _paused = !_paused);

  void startAnother() => setState(() => _finished = null);

  String get _clock {
    final remaining = (_planned * 60 - _elapsed).clamp(0, 1 << 30);
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_session != null) return _RunningView(state: this);
    if (_finished != null) return _SummaryView(state: this, session: _finished!);
    return _SetupView(state: this);
  }
}

class _SetupView extends ConsumerWidget {
  const _SetupView({required this.state});
  final _FocusPageState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final assignments =
        ref.watch(assignmentsProvider(state._subjectId)).value ?? const <Assignment>[];
    final open = assignments.where((a) => !a.isDone).toList();
    final text = Theme.of(context).textTheme;

    return PageBody(
      children: [
        const PageTitle('Fokus', subtitle: 'Vælg hvad du arbejder med, og hvor længe.'),
        Text('Hvor længe', style: text.labelSmall),
        const SizedBox(height: 8),
        ChoiceRow<int>(
          selected: state._planned,
          onSelected: state.setPlanned,
          options: const [
            (value: 15, label: '15 min'),
            (value: 25, label: '25 min'),
            (value: 45, label: '45 min'),
            (value: 60, label: '60 min'),
          ],
        ),
        if (subjects.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Fag', style: text.labelSmall),
          const SizedBox(height: 8),
          ChoiceRow<int?>(
            selected: state._subjectId,
            onSelected: state.setSubject,
            options: [
              (value: null, label: 'Ikke et bestemt fag'),
              for (final subject in subjects) (value: subject.id, label: subject.name),
            ],
          ),
        ],
        if (open.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Opgave', style: text.labelSmall),
          const SizedBox(height: 8),
          ChoiceRow<int?>(
            selected: state._assignmentId,
            onSelected: state.setAssignment,
            options: [
              (value: null, label: 'Ingen bestemt opgave'),
              for (final assignment in open.take(6))
                (value: assignment.id, label: assignment.title),
            ],
          ),
        ],
        const SizedBox(height: 34),
        AppButton(
          label: 'Start ${state._planned} minutter',
          tone: ButtonTone.primary,
          expand: true,
          onPressed: state._start,
        ),
      ],
    );
  }
}

/// While the timer runs there is nothing on screen but the timer.
class _RunningView extends ConsumerWidget {
  const _RunningView({required this.state});
  final _FocusPageState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final subject = state._subjectId == null
        ? null
        : (ref.watch(subjectsProvider).value ?? const <Subject>[])
            .where((s) => s.id == state._subjectId)
            .firstOrNull;

    final progress = state._elapsed / (state._planned * 60);

    return Container(
      color: colors.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: context.pageInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subject != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SubjectDot(token: subject.colorToken),
                      const SizedBox(width: 8),
                      Text(subject.name, style: text.labelMedium),
                    ],
                  ),
                  const SizedBox(height: 26),
                ],
                Text(
                  state._clock,
                  style: text.displaySmall!.copyWith(
                    fontSize: 76,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 30),
                ProgressBar(value: progress, height: 3),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppButton(
                      label: state._paused ? 'Fortsæt' : 'Pause',
                      onPressed: state.togglePause,
                    ),
                    const SizedBox(width: 12),
                    AppButton(
                      label: 'Stop',
                      onPressed: () => state._stop(completed: false),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Notifikationer styres af dit system — TeenBrain sender ingen.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryView extends ConsumerWidget {
  const _SummaryView({required this.state, required this.session});

  final _FocusPageState state;
  final FocusSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final nav = ref.read(navigationProvider.notifier);
    final subject = session.subjectId == null
        ? null
        : (ref.watch(subjectsProvider).value ?? const <Subject>[])
            .where((s) => s.id == session.subjectId)
            .firstOrNull;

    return PageBody(
      children: [
        const SizedBox(height: 20),
        Text(session.durationLine, style: text.displaySmall),
        const SizedBox(height: 10),
        Text(
          subject == null
              ? session.completed
                  ? 'Sessionen kørte helt ud.'
                  : 'Du stoppede undervejs. Det tæller også.'
              : 'Du arbejdede med ${subject.name}.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: 30),
        if (session.minutes >= 1)
          Panel(
            accent: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('+${session.minutes} XP', style: text.titleMedium),
                const SizedBox(height: 4),
                Text('Registreret i din timeline og din uge.', style: text.bodyMedium),
              ],
            ),
          ),
        const SizedBox(height: 26),
        const SectionHeading('Hvad nu'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AppButton(
              label: 'En omgang mere',
              tone: ButtonTone.primary,
              onPressed: state.startAnother,
            ),
            if (subject != null)
              AppButton(
                label: 'Quiz i ${subject.name}',
                onPressed: () => nav.go(SubjectDetailRoute(subject.id)),
              ),
            AppButton(label: 'Hjem', onPressed: () => nav.go(const HomeRoute())),
          ],
        ),
      ],
    );
  }
}
