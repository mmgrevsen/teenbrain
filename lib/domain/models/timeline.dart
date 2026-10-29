/// The timeline is the spine: everything the user does writes one row here, and
/// the Timeline page, the dashboard and the search index all read from it.
library;

import 'package:meta/meta.dart';

enum TimelineKind { study, quiz, note, chat, focus, breakTime, screen }

extension TimelineKindCodec on TimelineKind {
  String get code => switch (this) {
        TimelineKind.breakTime => 'break',
        _ => name,
      };

  String get label => switch (this) {
        TimelineKind.study => 'Læring',
        TimelineKind.quiz => 'Quiz',
        TimelineKind.note => 'Note',
        TimelineKind.chat => 'Samtale',
        TimelineKind.focus => 'Fokus',
        TimelineKind.breakTime => 'Pause',
        TimelineKind.screen => 'Skærm',
      };

  static TimelineKind parse(String? code) => switch (code) {
        'quiz' => TimelineKind.quiz,
        'note' => TimelineKind.note,
        'chat' => TimelineKind.chat,
        'focus' => TimelineKind.focus,
        'break' => TimelineKind.breakTime,
        'screen' => TimelineKind.screen,
        _ => TimelineKind.study,
      };
}

@immutable
class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.kind,
    this.subjectId,
    this.subjectName,
    this.refTable,
    this.refId,
    required this.title,
    this.summary,
    required this.startedAt,
    this.endedAt,
  });

  final int id;
  final TimelineKind kind;
  final int? subjectId;

  /// Joined in by the repository so a timeline row can render without a second
  /// query per line.
  final String? subjectName;

  /// What to open when the row is tapped.
  final String? refTable;
  final int? refId;

  final String title;
  final String? summary;
  final DateTime startedAt;
  final DateTime? endedAt;

  Duration? get duration => endedAt?.difference(startedAt);

  bool get isOpenable => refTable != null && refId != null;
}

/// Events for one calendar day, newest first — the shape the Timeline renders.
@immutable
class TimelineDay {
  const TimelineDay({required this.day, required this.events});

  final DateTime day;
  final List<TimelineEvent> events;

  int get totalMinutes => events
      .map((e) => e.duration?.inMinutes ?? 0)
      .fold(0, (a, b) => a + b);
}
