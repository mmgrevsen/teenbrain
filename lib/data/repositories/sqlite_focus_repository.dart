import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/focus.dart';
import '../../domain/repositories/focus_repository.dart';
import '../db/local_database.dart';
import 'sql_support.dart';

class SqliteFocusRepository implements FocusRepository {
  SqliteFocusRepository(this._local);

  final LocalDatabase _local;
  Database get _db => _local.db;

  @override
  Future<FocusSession?> openSession() async {
    final rows = _db.select(
      'SELECT * FROM focus_sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1',
    );
    return rows.isEmpty ? null : _map(rows.first);
  }

  @override
  Future<FocusSession> start({
    int? subjectId,
    int? topicId,
    int? assignmentId,
    int plannedMinutes = 25,
  }) async {
    // Only one session can be open at a time. A session left running by a crash
    // is closed off at its own start time rather than counted as hours of work.
    final stale = await openSession();
    if (stale != null) {
      await finish(stale.id, actualSeconds: stale.actualSeconds, completed: false);
    }

    _db.execute(
      'INSERT INTO focus_sessions '
      '(subject_id, topic_id, assignment_id, started_at, planned_minutes) '
      'VALUES (?, ?, ?, ?, ?)',
      [subjectId, topicId, assignmentId, ms(DateTime.now()), plannedMinutes],
    );
    return (await session(_db.lastInsertRowId))!;
  }

  @override
  Future<FocusSession> finish(int id, {required int actualSeconds, required bool completed}) async {
    _db.execute(
      'UPDATE focus_sessions SET ended_at = ?, actual_seconds = ?, completed = ? WHERE id = ?',
      [ms(DateTime.now()), actualSeconds, boolTo(completed), id],
    );
    return (await session(id))!;
  }

  @override
  Future<List<FocusSession>> recent({int limit = 20}) async {
    return _db
        .select('SELECT * FROM focus_sessions ORDER BY started_at DESC LIMIT ?', [limit])
        .map(_map)
        .toList();
  }

  @override
  Future<FocusSession?> session(int id) async {
    final rows = _db.select('SELECT * FROM focus_sessions WHERE id = ?', [id]);
    return rows.isEmpty ? null : _map(rows.first);
  }

  @override
  Future<int> minutesSince(DateTime since, {int? subjectId}) async {
    final args = <Object?>[ms(since)];
    var clause = '';
    if (subjectId != null) {
      clause = 'AND subject_id = ?';
      args.add(subjectId);
    }
    final row = _db.select(
      'SELECT COALESCE(SUM(actual_seconds), 0) AS s FROM focus_sessions '
      'WHERE started_at >= ? $clause',
      args,
    ).first;
    return intOf(row['s']) ~/ 60;
  }

  FocusSession _map(Row row) => FocusSession(
        id: intOf(row['id']),
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        topicId: row['topic_id'] == null ? null : intOf(row['topic_id']),
        assignmentId: row['assignment_id'] == null ? null : intOf(row['assignment_id']),
        startedAt: timeOf(row['started_at']),
        endedAt: timeOrNull(row['ended_at']),
        plannedMinutes: intOf(row['planned_minutes']),
        actualSeconds: intOf(row['actual_seconds']),
        completed: boolOf(row['completed']),
        notes: row['notes'] as String?,
      );
}
