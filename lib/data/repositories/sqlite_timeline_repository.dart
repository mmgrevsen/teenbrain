import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/search.dart';
import '../../domain/models/timeline.dart';
import '../../domain/repositories/search_index.dart';
import '../../domain/repositories/timeline_repository.dart';
import '../db/local_database.dart';
import 'sql_support.dart';

class SqliteTimelineRepository implements TimelineRepository {
  SqliteTimelineRepository(this._local, {SearchIndex? searchIndex}) : _search = searchIndex;

  final LocalDatabase _local;
  final SearchIndex? _search;
  Database get _db => _local.db;

  @override
  Future<TimelineEvent> record({
    required TimelineKind kind,
    required String title,
    String? summary,
    int? subjectId,
    String? refTable,
    int? refId,
    DateTime? startedAt,
    DateTime? endedAt,
  }) async {
    _db.execute(
      'INSERT INTO timeline_events '
      '(kind, subject_id, ref_table, ref_id, title, summary, started_at, ended_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        kind.code,
        subjectId,
        refTable,
        refId,
        title,
        summary,
        ms(startedAt ?? DateTime.now()),
        msOrNull(endedAt),
      ],
    );
    final created = (await event(_db.lastInsertRowId))!;
    await _search?.index(
      scope: SearchScope.timeline,
      refId: created.id,
      title: created.title,
      body: created.summary ?? '',
      subjectId: created.subjectId,
      occurredAt: created.startedAt,
    );
    return created;
  }

  @override
  Future<List<TimelineEvent>> events({
    DateTime? after,
    DateTime? before,
    int? subjectId,
    Set<TimelineKind>? kinds,
    int limit = 200,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (after != null) {
      where.add('e.started_at >= ?');
      args.add(ms(after));
    }
    if (before != null) {
      where.add('e.started_at <= ?');
      args.add(ms(before));
    }
    if (subjectId != null) {
      where.add('e.subject_id = ?');
      args.add(subjectId);
    }
    if (kinds != null && kinds.isNotEmpty) {
      where.add('e.kind IN (${placeholders(kinds.length)})');
      args.addAll(kinds.map((k) => k.code));
    }
    args.add(limit);

    final rows = _db.select(
      'SELECT e.*, s.name AS subject_name FROM timeline_events e '
      'LEFT JOIN subjects s ON s.id = e.subject_id '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'ORDER BY e.started_at DESC LIMIT ?',
      args,
    );
    return rows.map(_map).toList();
  }

  @override
  Future<List<TimelineDay>> days({int limit = 30}) async {
    // Grouping in Dart rather than SQL: local midnight is a timezone question,
    // and SQLite does not know the user's timezone.
    final all = await events(limit: limit * 40);
    final buckets = <DateTime, List<TimelineEvent>>{};
    for (final e in all) {
      buckets.putIfAbsent(startOfDay(e.startedAt), () => []).add(e);
    }
    final ordered = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in ordered.take(limit)) TimelineDay(day: day, events: buckets[day]!),
    ];
  }

  @override
  Future<TimelineEvent?> event(int id) async {
    final rows = _db.select(
      'SELECT e.*, s.name AS subject_name FROM timeline_events e '
      'LEFT JOIN subjects s ON s.id = e.subject_id WHERE e.id = ?',
      [id],
    );
    return rows.isEmpty ? null : _map(rows.first);
  }

  @override
  Future<void> delete(int id) async {
    _db.execute('DELETE FROM timeline_events WHERE id = ?', [id]);
    await _search?.remove(SearchScope.timeline, id);
  }

  @override
  Future<Map<int, DateTime>> lastTouchedPerSubject() async {
    final result = <int, DateTime>{};
    for (final row in _db.select(
      'SELECT subject_id, MAX(started_at) AS t FROM timeline_events '
      'WHERE subject_id IS NOT NULL GROUP BY subject_id',
    )) {
      result[intOf(row['subject_id'])] = timeOf(row['t']);
    }
    return result;
  }

  TimelineEvent _map(Row row) => TimelineEvent(
        id: intOf(row['id']),
        kind: TimelineKindCodec.parse(row['kind'] as String?),
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        subjectName: row['subject_name'] as String?,
        refTable: row['ref_table'] as String?,
        refId: row['ref_id'] == null ? null : intOf(row['ref_id']),
        title: row['title'] as String,
        summary: row['summary'] as String?,
        startedAt: timeOf(row['started_at']),
        endedAt: timeOrNull(row['ended_at']),
      );
}
