/// A focus session: one stretch of deliberate work.
library;

import 'package:meta/meta.dart';

@immutable
class FocusSession {
  const FocusSession({
    required this.id,
    this.subjectId,
    this.topicId,
    this.assignmentId,
    required this.startedAt,
    this.endedAt,
    this.plannedMinutes = 25,
    this.actualSeconds = 0,
    this.completed = false,
    this.notes,
  });

  final int id;
  final int? subjectId;
  final int? topicId;
  final int? assignmentId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int plannedMinutes;
  final int actualSeconds;

  /// True when the timer ran out, false when the user stopped early. Both are
  /// worth recording; only one of them is a completed session.
  final bool completed;

  final String? notes;

  bool get isRunning => endedAt == null;
  int get minutes => actualSeconds ~/ 60;

  /// "32 minutters fokus" — or seconds, when the session was very short, so a
  /// two-minute session does not read as "0 minutters fokus".
  String get durationLine {
    if (actualSeconds < 60) return '$actualSeconds sekunders fokus';
    return '$minutes minutters fokus';
  }
}
