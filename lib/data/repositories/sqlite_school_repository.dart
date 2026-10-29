import 'package:sqlite3/sqlite3.dart';

import '../../core/danish.dart';
import '../../domain/models/school.dart';
import '../../domain/repositories/school_repository.dart';
import '../db/local_database.dart';
import 'sql_support.dart';

class SqliteSchoolRepository implements SchoolRepository {
  SqliteSchoolRepository(this._local);

  final LocalDatabase _local;
  Database get _db => _local.db;

  // ------------------------------------------------------------- subjects

  @override
  Future<List<Subject>> subjects({bool includeArchived = false}) async {
    final rows = _db.select(
      'SELECT * FROM subjects ${includeArchived ? '' : 'WHERE archived = 0'} '
      'ORDER BY sort_order, name',
    );
    return rows.map(_subject).toList();
  }

  @override
  Future<Subject?> subject(int id) async {
    final rows = _db.select('SELECT * FROM subjects WHERE id = ?', [id]);
    return rows.isEmpty ? null : _subject(rows.first);
  }

  @override
  Future<Subject?> subjectByName(String name) async {
    final wanted = foldDanish(name.trim());
    if (wanted.isEmpty) return null;
    for (final row in _db.select('SELECT * FROM subjects')) {
      if (foldDanish(row['name'] as String) == wanted) return _subject(row);
    }
    return null;
  }

  @override
  Future<Subject> createSubject(String name, {String? colorToken}) async {
    final existing = await subjectByName(name);
    if (existing != null) return existing;

    final now = DateTime.now();
    final nextOrder = intOf(
      _db.select('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM subjects').first['n'],
    );
    _db.execute(
      'INSERT INTO subjects (name, color_token, sort_order, archived, created_at) '
      'VALUES (?, ?, ?, 0, ?)',
      [name.trim(), colorToken ?? _colorForOrder(nextOrder), nextOrder, ms(now)],
    );
    return (await subject(_db.lastInsertRowId))!;
  }

  @override
  Future<Subject> updateSubject(Subject subject) async {
    _db.execute(
      'UPDATE subjects SET name = ?, color_token = ?, sort_order = ?, archived = ? WHERE id = ?',
      [
        subject.name,
        subject.colorToken,
        subject.sortOrder,
        boolTo(subject.archived),
        subject.id,
      ],
    );
    return (await this.subject(subject.id))!;
  }

  @override
  Future<void> deleteSubject(int id) async {
    _db.execute('DELETE FROM subjects WHERE id = ?', [id]);
  }

  @override
  Future<void> reorderSubjects(List<int> idsInOrder) async {
    transact(_db, () {
      for (var i = 0; i < idsInOrder.length; i++) {
        _db.execute('UPDATE subjects SET sort_order = ? WHERE id = ?', [i, idsInOrder[i]]);
      }
    });
  }

  /// The theme's six subject colours, cycled. A seventh subject reuses the
  /// first — better than inventing a colour the palette has not been checked
  /// against in both light and dark mode.
  static const _palette = ['blue', 'violet', 'teal', 'amber', 'rose', 'green'];
  String _colorForOrder(int order) => _palette[order % _palette.length];

  // --------------------------------------------------------------- topics

  @override
  Future<List<Topic>> topics(int subjectId) async {
    final rows = _db.select(
      'SELECT * FROM topics WHERE subject_id = ? ORDER BY mastery, name',
      [subjectId],
    );
    return rows.map(_topic).toList();
  }

  @override
  Future<List<Topic>> allTopics() async {
    return _db.select('SELECT * FROM topics ORDER BY subject_id, name').map(_topic).toList();
  }

  @override
  Future<Topic?> topic(int id) async {
    final rows = _db.select('SELECT * FROM topics WHERE id = ?', [id]);
    return rows.isEmpty ? null : _topic(rows.first);
  }

  @override
  Future<Topic> ensureTopic(int subjectId, String name) async {
    final trimmed = name.trim();
    final wanted = foldDanish(trimmed);
    for (final row in _db.select('SELECT * FROM topics WHERE subject_id = ?', [subjectId])) {
      if (foldDanish(row['name'] as String) == wanted) return _topic(row);
    }

    final now = ms(DateTime.now());
    _db.execute(
      'INSERT INTO topics (subject_id, name, mastery, first_seen, created_at) '
      'VALUES (?, ?, 0, ?, ?)',
      [subjectId, trimmed, now, now],
    );
    return (await topic(_db.lastInsertRowId))!;
  }

  @override
  Future<Topic> recordMastery(int topicId, double observed, {double weight = 0.35}) async {
    final current = await topic(topicId);
    if (current == null) throw StateError('Emnet findes ikke længere.');

    // Exponential moving average. A single quiz moves the needle without
    // erasing everything that came before it.
    final blended = current.mastery == 0 && current.lastWorked == null
        ? observed
        : current.mastery * (1 - weight) + observed.clamp(0.0, 1.0) * weight;

    _db.execute(
      'UPDATE topics SET mastery = ?, last_worked = ? WHERE id = ?',
      [blended.clamp(0.0, 1.0), ms(DateTime.now()), topicId],
    );
    return (await topic(topicId))!;
  }

  @override
  Future<void> touchTopic(int topicId) async {
    _db.execute('UPDATE topics SET last_worked = ? WHERE id = ?', [ms(DateTime.now()), topicId]);
  }

  @override
  Future<void> deleteTopic(int id) async {
    _db.execute('DELETE FROM topics WHERE id = ?', [id]);
  }

  // ---------------------------------------------------------- assignments

  @override
  Future<List<Assignment>> assignments({bool includeCompleted = false, int? subjectId}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (!includeCompleted) where.add('completed_at IS NULL');
    if (subjectId != null) {
      where.add('subject_id = ?');
      args.add(subjectId);
    }
    final rows = _db.select(
      'SELECT * FROM assignments ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'ORDER BY due_at IS NULL, due_at, created_at DESC',
      args,
    );
    return rows.map(_assignment).toList();
  }

  @override
  Future<List<Assignment>> upcoming({int limit = 5}) async {
    final rows = _db.select(
      'SELECT * FROM assignments WHERE completed_at IS NULL AND due_at IS NOT NULL '
      'ORDER BY due_at LIMIT ?',
      [limit],
    );
    return rows.map(_assignment).toList();
  }

  @override
  Future<Assignment?> assignment(int id) async {
    final rows = _db.select('SELECT * FROM assignments WHERE id = ?', [id]);
    return rows.isEmpty ? null : _assignment(rows.first);
  }

  @override
  Future<Assignment> createAssignment({
    int? subjectId,
    required String title,
    String? description,
    DateTime? dueAt,
    int? estimatedMinutes,
  }) async {
    _db.execute(
      'INSERT INTO assignments '
      '(subject_id, title, description, due_at, estimated_minutes, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [subjectId, title.trim(), description, msOrNull(dueAt), estimatedMinutes, ms(DateTime.now())],
    );
    return (await assignment(_db.lastInsertRowId))!;
  }

  @override
  Future<Assignment> updateAssignment(Assignment a) async {
    _db.execute(
      'UPDATE assignments SET subject_id = ?, title = ?, description = ?, due_at = ?, '
      'estimated_minutes = ?, completed_at = ? WHERE id = ?',
      [
        a.subjectId,
        a.title,
        a.description,
        msOrNull(a.dueAt),
        a.estimatedMinutes,
        msOrNull(a.completedAt),
        a.id,
      ],
    );
    return (await assignment(a.id))!;
  }

  @override
  Future<void> setAssignmentDone(int id, bool done) async {
    _db.execute(
      'UPDATE assignments SET completed_at = ? WHERE id = ?',
      [done ? ms(DateTime.now()) : null, id],
    );
  }

  @override
  Future<void> deleteAssignment(int id) async {
    _db.execute('DELETE FROM assignments WHERE id = ?', [id]);
  }

  // ------------------------------------------------------------ summaries

  @override
  Future<List<SubjectSummary>> summaries() async {
    final all = await subjects();
    if (all.isEmpty) return const [];

    // Four grouped queries instead of four per subject.
    final topicsBySubject = <int, List<Topic>>{};
    for (final t in await allTopics()) {
      topicsBySubject.putIfAbsent(t.subjectId, () => []).add(t);
    }

    final openBySubject = <int, List<Assignment>>{};
    for (final a in await assignments()) {
      if (a.subjectId != null) openBySubject.putIfAbsent(a.subjectId!, () => []).add(a);
    }

    final weekAgo = ms(DateTime.now().subtract(const Duration(days: 7)));
    final minutes = <int, int>{};
    for (final row in _db.select(
      'SELECT subject_id, SUM(actual_seconds) AS s FROM focus_sessions '
      'WHERE subject_id IS NOT NULL AND started_at >= ? GROUP BY subject_id',
      [weekAgo],
    )) {
      minutes[intOf(row['subject_id'])] = intOf(row['s']) ~/ 60;
    }

    final answered = <int, int>{};
    final correct = <int, int>{};
    for (final row in _db.select(
      '''
      SELECT q.subject_id AS sid,
             COUNT(*)            AS n,
             SUM(a.correct)      AS c
      FROM quiz_answers a
      JOIN quiz_questions qq ON qq.id = a.question_id
      JOIN quizzes q         ON q.id  = qq.quiz_id
      WHERE q.subject_id IS NOT NULL
      GROUP BY q.subject_id
      ''',
    )) {
      final sid = intOf(row['sid']);
      answered[sid] = intOf(row['n']);
      correct[sid] = intOf(row['c']);
    }

    final lastStudied = <int, DateTime>{};
    for (final row in _db.select(
      'SELECT subject_id, MAX(started_at) AS t FROM timeline_events '
      'WHERE subject_id IS NOT NULL GROUP BY subject_id',
    )) {
      lastStudied[intOf(row['subject_id'])] = timeOf(row['t']);
    }

    return [
      for (final s in all)
        SubjectSummary(
          subject: s,
          topics: topicsBySubject[s.id] ?? const [],
          openAssignments: openBySubject[s.id] ?? const [],
          minutesLast7Days: minutes[s.id] ?? 0,
          questionsAnswered: answered[s.id] ?? 0,
          questionsCorrect: correct[s.id] ?? 0,
          lastStudied: lastStudied[s.id],
        ),
    ];
  }

  @override
  Future<SubjectSummary?> summary(int subjectId) async {
    final all = await summaries();
    for (final s in all) {
      if (s.subject.id == subjectId) return s;
    }
    return null;
  }

  // -------------------------------------------------------------- mapping

  Subject _subject(Row row) => Subject(
        id: intOf(row['id']),
        name: row['name'] as String,
        colorToken: row['color_token'] as String,
        sortOrder: intOf(row['sort_order']),
        archived: boolOf(row['archived']),
        createdAt: timeOf(row['created_at']),
      );

  Topic _topic(Row row) => Topic(
        id: intOf(row['id']),
        subjectId: intOf(row['subject_id']),
        name: row['name'] as String,
        mastery: doubleOf(row['mastery']),
        firstSeen: timeOf(row['first_seen']),
        lastWorked: timeOrNull(row['last_worked']),
      );

  Assignment _assignment(Row row) => Assignment(
        id: intOf(row['id']),
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        title: row['title'] as String,
        description: row['description'] as String?,
        dueAt: timeOrNull(row['due_at']),
        estimatedMinutes: row['estimated_minutes'] == null ? null : intOf(row['estimated_minutes']),
        completedAt: timeOrNull(row['completed_at']),
        createdAt: timeOf(row['created_at']),
      );
}
