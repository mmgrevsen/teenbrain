/// Gamification, kept quiet on purpose.
///
/// Streaks and levels work on teenagers because they are honest feedback about
/// consistency. They stop working the moment they feel like a children's game,
/// so: no confetti, no mascots, no badges shaped like stars.
library;

import 'package:meta/meta.dart';

@immutable
class DailyActivity {
  const DailyActivity({
    required this.day,
    this.minutesStudied = 0,
    this.questionsAnswered = 0,
    this.xpEarned = 0,
  });

  /// Midnight local time for the day this row covers.
  final DateTime day;

  final int minutesStudied;
  final int questionsAnswered;
  final int xpEarned;

  bool get isActive => minutesStudied > 0 || questionsAnswered > 0;
}

@immutable
class StreakInfo {
  const StreakInfo({required this.current, required this.longest, required this.activeToday});

  final int current;
  final int longest;
  final bool activeToday;

  /// "4 dage i træk"
  String get label => current == 1 ? '1 dag i træk' : '$current dage i træk';
}

@immutable
class Achievement {
  const Achievement({
    required this.code,
    required this.title,
    required this.description,
    required this.target,
    this.progress = 0,
    this.unlockedAt,
  });

  final String code;
  final String title;
  final String description;

  /// The raw number the achievement counts towards (minutes, sessions, days).
  final double target;

  final double progress;
  final DateTime? unlockedAt;

  bool get isUnlocked => unlockedAt != null;
  double get ratio => target == 0 ? 0 : (progress / target).clamp(0.0, 1.0);
}

/// The definitions. Kept in the domain so both the unlocking logic and the UI
/// read from one list.
const List<Achievement> kAchievementCatalogue = [
  Achievement(
    code: 'first_session',
    title: 'Første session',
    description: 'Gennemfør en fokus-session.',
    target: 1,
  ),
  Achievement(
    code: 'streak_7',
    title: 'En uge i træk',
    description: 'Vær aktiv syv dage i streg.',
    target: 7,
  ),
  Achievement(
    code: 'streak_30',
    title: 'En måned i træk',
    description: 'Vær aktiv tredive dage i streg.',
    target: 30,
  ),
  Achievement(
    code: 'ten_hours',
    title: 'Ti timer',
    description: 'Saml ti timers fokuseret arbejde.',
    target: 600,
  ),
  Achievement(
    code: 'hundred_questions',
    title: 'Hundrede spørgsmål',
    description: 'Besvar hundrede quizspørgsmål.',
    target: 100,
  ),
  Achievement(
    code: 'perfect_quiz',
    title: 'Fejlfri',
    description: 'Få alle rigtige i en quiz med mindst fem spørgsmål.',
    target: 1,
  ),
  Achievement(
    code: 'turned_around',
    title: 'Vendt om',
    description: 'Flyt et emne fra "mangler træning" til "stærk".',
    target: 1,
  ),
];

/// A week of activity, for the dashboard's progress strip.
@immutable
class WeeklyProgress {
  const WeeklyProgress({required this.days, required this.streak});

  /// Seven entries, oldest first, ending today.
  final List<DailyActivity> days;
  final StreakInfo streak;

  int get totalMinutes => days.fold(0, (a, d) => a + d.minutesStudied);
  int get activeDays => days.where((d) => d.isActive).length;
  int get busiestMinutes => days.fold(0, (a, d) => d.minutesStudied > a ? d.minutesStudied : a);
}
