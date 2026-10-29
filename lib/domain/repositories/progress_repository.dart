import '../models/progress.dart';

abstract class ProgressRepository {
  /// Adds to today's row, creating it if this is the first activity today.
  Future<void> logActivity({int minutes = 0, int questions = 0, int xp = 0});

  Future<DailyActivity> today();
  Future<List<DailyActivity>> lastDays(int count);
  Future<WeeklyProgress> week();
  Future<StreakInfo> streak();

  Future<List<Achievement>> achievements();

  /// Recomputes progress on every achievement and unlocks any that have been
  /// earned. Returns only the ones newly unlocked, so the UI can announce them.
  Future<List<Achievement>> refreshAchievements();

  /// Wipes activity, achievements and XP. Separate from deleting content —
  /// a user may want to reset their stats without losing their notes.
  Future<void> reset();
}
