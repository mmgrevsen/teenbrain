import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/progress.dart';
import '../../domain/repositories/progress_repository.dart';
import '../db/local_database.dart';
import 'sql_support.dart';

class SqliteProgressRepository implements ProgressRepository {
  SqliteProgressRepository(this._local);

  final LocalDatabase _local;
  Database get _db => _local.db;

  @override
  Future<void> logActivity({int minutes = 0, int questions = 0, int xp = 0}) async {
    if (minutes == 0 && questions == 0 && xp == 0) return;
    final day = ms(startOfDay(DateTime.now()));
    _db.execute(
      '''
      INSERT INTO daily_activity (day, minutes_studied, questions_answered, xp_earned)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(day) DO UPDATE SET
        minutes_studied    = minutes_studied + excluded.minutes_studied,
        questions_answered = questions_answered + excluded.questions_answered,
        xp_earned          = xp_earned + excluded.xp_earned
      ''',
      [day, minutes, questions, xp],
    );
  }

  @override
  Future<DailyActivity> today() async {
    final day = startOfDay(DateTime.now());
    final rows = _db.select('SELECT * FROM daily_activity WHERE day = ?', [ms(day)]);
    return rows.isEmpty ? DailyActivity(day: day) : _map(rows.first);
  }

  @override
  Future<List<DailyActivity>> lastDays(int count) async {
    final today = startOfDay(DateTime.now());
    final from = today.subtract(Duration(days: count - 1));
    final byDay = <DateTime, DailyActivity>{};
    for (final row in _db.select(
      'SELECT * FROM daily_activity WHERE day >= ? ORDER BY day',
      [ms(from)],
    )) {
      final activity = _map(row);
      byDay[activity.day] = activity;
    }

    // Gaps are days with no activity, not missing data — the streak logic and
    // the weekly strip both need a row for every day.
    return [
      for (var i = 0; i < count; i++)
        () {
          final day = from.add(Duration(days: i));
          return byDay[day] ?? DailyActivity(day: day);
        }(),
    ];
  }

  @override
  Future<WeeklyProgress> week() async {
    return WeeklyProgress(days: await lastDays(7), streak: await streak());
  }

  @override
  Future<StreakInfo> streak() async {
    final rows = _db.select(
      'SELECT day FROM daily_activity '
      'WHERE minutes_studied > 0 OR questions_answered > 0 ORDER BY day DESC',
    );
    final days = rows.map((r) => timeOf(r['day'])).toList();
    if (days.isEmpty) {
      return const StreakInfo(current: 0, longest: 0, activeToday: false);
    }

    final today = startOfDay(DateTime.now());
    final active = days.toSet();
    final activeToday = active.contains(today);

    // A streak stays alive until the end of the following day: someone who
    // studied last night and has not started yet today has not lost it.
    var cursor = activeToday ? today : today.subtract(const Duration(days: 1));
    var current = 0;
    while (active.contains(cursor)) {
      current++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    var longest = 0;
    var run = 0;
    DateTime? previous;
    for (final day in days.reversed) {
      if (previous != null && day.difference(previous).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
      previous = day;
    }

    return StreakInfo(current: current, longest: longest, activeToday: activeToday);
  }

  @override
  Future<List<Achievement>> achievements() async {
    final stored = <String, ({DateTime? unlockedAt, double progress})>{};
    for (final row in _db.select('SELECT * FROM achievements')) {
      stored[row['code'] as String] =
          (unlockedAt: timeOrNull(row['unlocked_at']), progress: doubleOf(row['progress']));
    }
    return [
      for (final a in kAchievementCatalogue)
        Achievement(
          code: a.code,
          title: a.title,
          description: a.description,
          target: a.target,
          progress: stored[a.code]?.progress ?? 0,
          unlockedAt: stored[a.code]?.unlockedAt,
        ),
    ];
  }

  @override
  Future<List<Achievement>> refreshAchievements() async {
    final progress = await _measure();
    final existing = await achievements();
    final now = DateTime.now();
    final unlocked = <Achievement>[];

    transact(_db, () {
      for (final a in existing) {
        final value = progress[a.code] ?? a.progress;
        final earned = value >= a.target;
        final justUnlocked = earned && !a.isUnlocked;

        _db.execute(
          'INSERT INTO achievements (code, unlocked_at, progress) VALUES (?, ?, ?) '
          'ON CONFLICT(code) DO UPDATE SET '
          '  progress = excluded.progress, '
          '  unlocked_at = COALESCE(achievements.unlocked_at, excluded.unlocked_at)',
          [a.code, earned ? ms(a.unlockedAt ?? now) : null, value],
        );

        if (justUnlocked) {
          unlocked.add(Achievement(
            code: a.code,
            title: a.title,
            description: a.description,
            target: a.target,
            progress: value,
            unlockedAt: now,
          ));
        }
      }
    });

    return unlocked;
  }

  /// The raw numbers each achievement counts. One query per measure, run only
  /// when something has actually happened.
  Future<Map<String, double>> _measure() async {
    double scalar(String sql) => doubleOf(_db.select(sql).first.values.first);

    final streakInfo = await streak();

    return {
      'first_session':
          scalar('SELECT COUNT(*) FROM focus_sessions WHERE completed = 1').clamp(0, 1),
      'streak_7': streakInfo.longest.toDouble(),
      'streak_30': streakInfo.longest.toDouble(),
      'ten_hours': scalar('SELECT COALESCE(SUM(actual_seconds), 0) / 60 FROM focus_sessions'),
      'hundred_questions': scalar('SELECT COUNT(*) FROM quiz_answers'),
      'perfect_quiz': scalar(
        'SELECT COUNT(*) FROM quiz_attempts '
        'WHERE finished_at IS NOT NULL AND total >= 5 AND score = total',
      ).clamp(0, 1),
      'turned_around': scalar('SELECT COUNT(*) FROM topics WHERE mastery >= 0.75').clamp(0, 1),
    };
  }

  @override
  Future<void> reset() async {
    transact(_db, () {
      _db.execute('DELETE FROM daily_activity');
      _db.execute('DELETE FROM achievements');
      _db.execute('UPDATE profile SET xp = 0 WHERE id = 1');
    });
  }

  DailyActivity _map(Row row) => DailyActivity(
        day: timeOf(row['day']),
        minutesStudied: intOf(row['minutes_studied']),
        questionsAnswered: intOf(row['questions_answered']),
        xpEarned: intOf(row['xp_earned']),
      );
}
