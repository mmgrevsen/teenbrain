import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/quiz.dart';
import '../../domain/models/search.dart';
import '../../domain/repositories/quiz_repository.dart';
import '../../domain/repositories/search_index.dart';
import '../db/local_database.dart';
import 'sql_support.dart';

class SqliteQuizRepository implements QuizRepository {
  SqliteQuizRepository(this._local, {SearchIndex? searchIndex}) : _search = searchIndex;

  final LocalDatabase _local;
  final SearchIndex? _search;
  Database get _db => _local.db;

  @override
  Future<List<Quiz>> quizzes({int? subjectId, int limit = 100}) async {
    final rows = subjectId == null
        ? _db.select('SELECT * FROM quizzes ORDER BY created_at DESC LIMIT ?', [limit])
        : _db.select(
            'SELECT * FROM quizzes WHERE subject_id = ? ORDER BY created_at DESC LIMIT ?',
            [subjectId, limit],
          );
    return rows.map((r) => _quiz(r, const [])).toList();
  }

  @override
  Future<Quiz?> quiz(int id) async {
    final rows = _db.select('SELECT * FROM quizzes WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _quiz(rows.first, await _questions(id));
  }

  Future<List<QuizQuestion>> _questions(int quizId) async {
    return _db
        .select('SELECT * FROM quiz_questions WHERE quiz_id = ? ORDER BY position, id', [quizId])
        .map(_question)
        .toList();
  }

  @override
  Future<Quiz> create({
    required String title,
    int? subjectId,
    int? topicId,
    String sourceKind = 'topic',
    String? sourceRef,
    required List<QuizQuestion> questions,
  }) async {
    if (questions.isEmpty) {
      throw ArgumentError('En quiz uden spørgsmål kan ikke gemmes.');
    }
    final now = ms(DateTime.now());

    final id = transact(_db, () {
      _db.execute(
        'INSERT INTO quizzes (subject_id, topic_id, title, source_kind, source_ref, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [subjectId, topicId, title.trim(), sourceKind, sourceRef, now],
      );
      final quizId = _db.lastInsertRowId;
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        _db.execute(
          'INSERT INTO quiz_questions '
          '(quiz_id, kind, prompt, options_json, answer, explanation, position) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            quizId,
            q.kind.code,
            q.prompt,
            q.options.isEmpty ? null : jsonEncode(q.options),
            q.answer,
            q.explanation,
            i,
          ],
        );
      }
      return quizId;
    });

    final created = (await quiz(id))!;
    await _search?.index(
      scope: SearchScope.quiz,
      refId: created.id,
      title: created.title,
      body: created.questions.map((q) => q.prompt).join('\n'),
      subjectId: created.subjectId,
      occurredAt: created.createdAt,
    );
    return created;
  }

  @override
  Future<void> deleteQuiz(int id) async {
    _db.execute('DELETE FROM quizzes WHERE id = ?', [id]);
    await _search?.remove(SearchScope.quiz, id);
  }

  // -------------------------------------------------------------- attempts

  @override
  Future<QuizAttempt> startAttempt(int quizId) async {
    final total = intOf(
      _db.select('SELECT COUNT(*) AS n FROM quiz_questions WHERE quiz_id = ?', [quizId]).first['n'],
    );
    _db.execute(
      'INSERT INTO quiz_attempts (quiz_id, started_at, score, total) VALUES (?, ?, 0, ?)',
      [quizId, ms(DateTime.now()), total],
    );
    return (await attempt(_db.lastInsertRowId))!;
  }

  @override
  Future<void> recordAnswer({
    required int attemptId,
    required int questionId,
    required String given,
    required bool correct,
    String? aiFeedback,
  }) async {
    transact(_db, () {
      // Re-answering the same question replaces the earlier row rather than
      // scoring it twice.
      _db.execute(
        'DELETE FROM quiz_answers WHERE attempt_id = ? AND question_id = ?',
        [attemptId, questionId],
      );
      _db.execute(
        'INSERT INTO quiz_answers (attempt_id, question_id, given, correct, ai_feedback) '
        'VALUES (?, ?, ?, ?, ?)',
        [attemptId, questionId, given, boolTo(correct), aiFeedback],
      );
      _db.execute(
        'UPDATE quiz_attempts SET score = '
        '(SELECT COALESCE(SUM(correct), 0) FROM quiz_answers WHERE attempt_id = ?) '
        'WHERE id = ?',
        [attemptId, attemptId],
      );
    });
  }

  @override
  Future<QuizAttempt> finishAttempt(int attemptId) async {
    _db.execute(
      'UPDATE quiz_attempts SET finished_at = ? WHERE id = ?',
      [ms(DateTime.now()), attemptId],
    );
    return (await attempt(attemptId))!;
  }

  @override
  Future<QuizAttempt?> attempt(int id) async {
    final rows = _db.select('SELECT * FROM quiz_attempts WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return _attempt(rows.first, _answersFor(id));
  }

  @override
  Future<List<QuizAttempt>> attemptsFor(int quizId) async {
    return _db
        .select('SELECT * FROM quiz_attempts WHERE quiz_id = ? ORDER BY started_at DESC', [quizId])
        .map((r) => _attempt(r, _answersFor(intOf(r['id']))))
        .toList();
  }

  List<QuizAnswer> _answersFor(int attemptId) {
    return _db
        .select('SELECT * FROM quiz_answers WHERE attempt_id = ? ORDER BY id', [attemptId])
        .map((r) => QuizAnswer(
              questionId: intOf(r['question_id']),
              given: r['given'] as String? ?? '',
              correct: boolOf(r['correct']),
              aiFeedback: r['ai_feedback'] as String?,
            ))
        .toList();
  }

  @override
  Future<List<QuizQuestion>> recentMistakes({int? subjectId, int limit = 20}) async {
    final args = <Object?>[];
    final subjectClause = subjectId == null ? '' : 'AND q.subject_id = ?';
    if (subjectId != null) args.add(subjectId);
    args.add(limit);

    final rows = _db.select(
      '''
      SELECT qq.*
      FROM quiz_answers a
      JOIN quiz_questions qq ON qq.id = a.question_id
      JOIN quizzes q         ON q.id  = qq.quiz_id
      JOIN quiz_attempts at  ON at.id = a.attempt_id
      WHERE a.correct = 0 $subjectClause
      ORDER BY at.started_at DESC
      LIMIT ?
      ''',
      args,
    );
    return rows.map(_question).toList();
  }

  @override
  Future<({int answered, int correct})> accuracyFor(int subjectId, {DateTime? since}) async {
    final args = <Object?>[subjectId];
    var clause = '';
    if (since != null) {
      clause = 'AND at.started_at >= ?';
      args.add(ms(since));
    }
    final row = _db.select(
      '''
      SELECT COUNT(*) AS n, COALESCE(SUM(a.correct), 0) AS c
      FROM quiz_answers a
      JOIN quiz_questions qq ON qq.id = a.question_id
      JOIN quizzes q         ON q.id  = qq.quiz_id
      JOIN quiz_attempts at  ON at.id = a.attempt_id
      WHERE q.subject_id = ? $clause
      ''',
      args,
    ).first;
    return (answered: intOf(row['n']), correct: intOf(row['c']));
  }

  // -------------------------------------------------------------- mapping

  Quiz _quiz(Row row, List<QuizQuestion> questions) => Quiz(
        id: intOf(row['id']),
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        topicId: row['topic_id'] == null ? null : intOf(row['topic_id']),
        title: row['title'] as String,
        sourceKind: row['source_kind'] as String? ?? 'topic',
        sourceRef: row['source_ref'] as String?,
        createdAt: timeOf(row['created_at']),
        questions: questions,
      );

  QuizQuestion _question(Row row) {
    final raw = row['options_json'] as String?;
    return QuizQuestion(
      id: intOf(row['id']),
      quizId: intOf(row['quiz_id']),
      kind: QuestionKindCodec.parse(row['kind'] as String?),
      prompt: row['prompt'] as String,
      options: raw == null ? const [] : (jsonDecode(raw) as List).map((e) => '$e').toList(),
      answer: row['answer'] as String,
      explanation: row['explanation'] as String?,
      position: intOf(row['position']),
    );
  }

  QuizAttempt _attempt(Row row, List<QuizAnswer> answers) => QuizAttempt(
        id: intOf(row['id']),
        quizId: intOf(row['quiz_id']),
        startedAt: timeOf(row['started_at']),
        finishedAt: timeOrNull(row['finished_at']),
        score: intOf(row['score']),
        total: intOf(row['total']),
        answers: answers,
      );
}
