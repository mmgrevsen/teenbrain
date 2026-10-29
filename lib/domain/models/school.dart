/// Subjects, the topics inside them, and the work that is due.
library;

import 'package:meta/meta.dart';

@immutable
class Subject {
  const Subject({
    required this.id,
    required this.name,
    this.colorToken = 'blue',
    this.sortOrder = 0,
    this.archived = false,
    required this.createdAt,
  });

  final int id;
  final String name;

  /// A name from the theme's subject palette, not a hex value — the colour has
  /// to resolve differently in light and dark mode.
  final String colorToken;

  final int sortOrder;
  final bool archived;
  final DateTime createdAt;

  Subject copyWith({String? name, String? colorToken, int? sortOrder, bool? archived}) => Subject(
        id: id,
        name: name ?? this.name,
        colorToken: colorToken ?? this.colorToken,
        sortOrder: sortOrder ?? this.sortOrder,
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );
}

@immutable
class Topic {
  const Topic({
    required this.id,
    required this.subjectId,
    required this.name,
    this.mastery = 0,
    required this.firstSeen,
    this.lastWorked,
  });

  final int id;
  final int subjectId;
  final String name;

  /// 0..1. Moved by quiz results and study sessions, never guessed by the UI.
  final double mastery;

  final DateTime firstSeen;
  final DateTime? lastWorked;

  /// The three buckets the Subjects page groups topics into.
  MasteryBand get band {
    if (mastery >= 0.75) return MasteryBand.strong;
    if (mastery >= 0.4) return MasteryBand.current;
    return MasteryBand.needsWork;
  }

  int? daysSinceWorked(DateTime now) {
    if (lastWorked == null) return null;
    return now.difference(lastWorked!).inDays;
  }
}

enum MasteryBand { needsWork, current, strong }

extension MasteryBandLabel on MasteryBand {
  String get label => switch (this) {
        MasteryBand.needsWork => 'Mangler træning',
        MasteryBand.current => 'Aktuelt',
        MasteryBand.strong => 'Stærk',
      };
}

@immutable
class Assignment {
  const Assignment({
    required this.id,
    this.subjectId,
    required this.title,
    this.description,
    this.dueAt,
    this.estimatedMinutes,
    this.completedAt,
    required this.createdAt,
  });

  final int id;
  final int? subjectId;
  final String title;
  final String? description;
  final DateTime? dueAt;
  final int? estimatedMinutes;
  final DateTime? completedAt;
  final DateTime createdAt;

  bool get isDone => completedAt != null;

  bool isOverdue(DateTime now) => !isDone && dueAt != null && dueAt!.isBefore(now);

  /// Whole days until it is due; negative when it is late. Null with no date.
  int? daysUntilDue(DateTime now) {
    if (dueAt == null) return null;
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(dueAt!.year, dueAt!.month, dueAt!.day);
    return b.difference(a).inDays;
  }
}

/// A subject with the numbers the Subjects page shows next to it.
@immutable
class SubjectSummary {
  const SubjectSummary({
    required this.subject,
    required this.topics,
    required this.openAssignments,
    required this.minutesLast7Days,
    required this.questionsAnswered,
    required this.questionsCorrect,
    this.lastStudied,
  });

  final Subject subject;
  final List<Topic> topics;
  final List<Assignment> openAssignments;
  final int minutesLast7Days;
  final int questionsAnswered;
  final int questionsCorrect;
  final DateTime? lastStudied;

  double? get accuracy => questionsAnswered == 0 ? null : questionsCorrect / questionsAnswered;

  List<Topic> get current => topics.where((t) => t.band == MasteryBand.current).toList();
  List<Topic> get needsWork => topics.where((t) => t.band == MasteryBand.needsWork).toList();
  List<Topic> get strong => topics.where((t) => t.band == MasteryBand.strong).toList();
}
