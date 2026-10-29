import 'package:sqlite3/sqlite3.dart';

import '../../core/danish.dart';
import '../../core/fuzzy.dart';
import '../../domain/models/search.dart';
import '../../domain/repositories/search_index.dart';
import '../db/local_database.dart';
import 'sql_support.dart';

/// One index for everything searchable.
///
/// FTS5 is used when the bundled SQLite has it — which is checked by actually
/// creating the table, not by trusting a version number. When it does not, the
/// same queries run against a folded-text column with LIKE plus the fuzzy
/// scorer. Slower on a large corpus, identical results shape, never broken.
class SqliteSearchIndex implements SearchIndex {
  SqliteSearchIndex(this._local);

  final LocalDatabase _local;
  Database get _db => _local.db;

  bool _fts = false;
  bool _probed = false;

  @override
  bool get hasFullTextSearch => _fts;

  /// Must run once before the index is used. Called from bootstrap.
  Future<void> initialize() async {
    if (_probed) return;
    _probed = true;
    try {
      // Deliberately not an external-content or contentless table. Those save
      // disk but make deletion a command that must be handed the row's original
      // values, and a 'delete' for a row that was never inserted corrupts the
      // index. A plain FTS5 table costs a copy of the text and lets deletion be
      // an ordinary DELETE.
      _db.execute(
        'CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5('
        "  title, body, tokenize='unicode61 remove_diacritics 2')",
      );
      _fts = true;
    } catch (_) {
      // No FTS5 in this build. The LIKE path below carries the feature.
      _fts = false;
    }
  }

  @override
  Future<void> index({
    required SearchScope scope,
    required int refId,
    required String title,
    String body = '',
    int? subjectId,
    required DateTime occurredAt,
  }) async {
    final folded = foldDanish('$title $body');

    transact(_db, () {
      _db.execute(
        '''
        INSERT INTO search_map (ref_table, ref_id, subject_id, occurred_at, title, body, folded)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(ref_table, ref_id) DO UPDATE SET
          subject_id  = excluded.subject_id,
          occurred_at = excluded.occurred_at,
          title       = excluded.title,
          body        = excluded.body,
          folded      = excluded.folded
        ''',
        [scope.table, refId, subjectId, ms(occurredAt), title, body, folded],
      );

      if (_fts) {
        final rowid = intOf(
          _db.select(
            'SELECT id FROM search_map WHERE ref_table = ? AND ref_id = ?',
            [scope.table, refId],
          ).first['id'],
        );
        // Folded text goes into the index, because folded terms come out of
        // the query. Index "haandvaerk" and a search for "håndværk",
        // "Haandvaerk" or "handvark" all land on it. The readable text stays
        // in search_map, which is where snippets are cut from.
        _db.execute('DELETE FROM search_fts WHERE rowid = ?', [rowid]);
        _db.execute(
          'INSERT INTO search_fts(rowid, title, body) VALUES (?, ?, ?)',
          [rowid, foldDanish(title), foldDanish(body)],
        );
      }
    });
  }

  @override
  Future<void> remove(SearchScope scope, int refId) async {
    final rows = _db.select(
      'SELECT id FROM search_map WHERE ref_table = ? AND ref_id = ?',
      [scope.table, refId],
    );
    if (rows.isEmpty) return;
    final rowid = intOf(rows.first['id']);

    transact(_db, () {
      if (_fts) _db.execute('DELETE FROM search_fts WHERE rowid = ?', [rowid]);
      _db.execute('DELETE FROM search_map WHERE id = ?', [rowid]);
    });
  }

  @override
  Future<List<SearchHit>> query(
    SearchInterpretation interpretation, {
    Set<SearchScope>? scopes,
    int limit = 40,
  }) async {
    final terms = interpretation.terms
        .map(foldDanish)
        .where((t) => t.length > 1)
        .toList();

    var rows = _fts && terms.isNotEmpty
        ? _ftsRows(terms, interpretation, scopes, limit)
        : _likeRows(terms, interpretation, scopes, limit);

    // Both the index and LIKE match on whole tokens. Neither finds "brøker"
    // for someone who typed "broker" on a keyboard they could not be bothered
    // to switch — the fold makes that "broeker" against "broker", one letter
    // apart. So when an exact path comes back empty, fall through to a scan
    // that scores every row with the fuzzy matcher. It is a table scan, and it
    // only runs when the cheap path already failed.
    if (rows.isEmpty && terms.isNotEmpty) {
      rows = _fuzzyRows(terms, interpretation, scopes);
    }

    final hits = <SearchHit>[];
    for (final row in rows) {
      final scope = SearchScopeCodec.fromTable(row['ref_table'] as String);
      if (scope == null) continue;

      final title = row['title'] as String;
      final body = row['body'] as String? ?? '';
      hits.add(SearchHit(
        scope: scope,
        refId: intOf(row['ref_id']),
        title: title,
        snippet: _snippet(body.isEmpty ? title : body, terms),
        occurredAt: timeOf(row['occurred_at']),
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        subjectName: row['subject_name'] as String?,
        score: _rank(title, body, terms, timeOf(row['occurred_at'])),
      ));
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  List<Row> _ftsRows(
    List<String> terms,
    SearchInterpretation interpretation,
    Set<SearchScope>? scopes,
    int limit,
  ) {
    // Prefix-match every term so "fotosyn" finds "fotosyntese". Terms are
    // quoted so a stray FTS operator in user input cannot change the query.
    final match = terms.map((t) => '"${t.replaceAll('"', '')}"*').join(' OR ');
    final where = <String>['m.id IN (SELECT rowid FROM search_fts WHERE search_fts MATCH ?)'];
    final args = <Object?>[match];
    _applyFilters(interpretation, scopes, where, args);
    args.add(limit * 3);

    return _db.select(
      'SELECT m.*, s.name AS subject_name FROM search_map m '
      'LEFT JOIN subjects s ON s.id = m.subject_id '
      'WHERE ${where.join(' AND ')} ORDER BY m.occurred_at DESC LIMIT ?',
      args,
    ).toList();
  }

  List<Row> _likeRows(
    List<String> terms,
    SearchInterpretation interpretation,
    Set<SearchScope>? scopes,
    int limit,
  ) {
    final where = <String>[];
    final args = <Object?>[];

    if (terms.isNotEmpty) {
      // Each term must appear, so more words narrows rather than widens.
      // Fuzzy scoring happens afterwards, in _rank.
      where.add('(${terms.map((_) => 'm.folded LIKE ?').join(' OR ')})');
      args.addAll(terms.map((t) => '%$t%'));
    }
    _applyFilters(interpretation, scopes, where, args);
    args.add(limit * 5);

    return _db.select(
      'SELECT m.*, s.name AS subject_name FROM search_map m '
      'LEFT JOIN subjects s ON s.id = m.subject_id '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'ORDER BY m.occurred_at DESC LIMIT ?',
      args,
    );
  }

  /// Last resort: every row that passes the filters, scored word by word with
  /// the fuzzy matcher. Bounded by [_fuzzyScanLimit] so a large archive cannot
  /// turn one search into a stall.
  static const int _fuzzyScanLimit = 4000;
  static const double _fuzzyFloor = 0.62;

  List<Row> _fuzzyRows(
    List<String> terms,
    SearchInterpretation interpretation,
    Set<SearchScope>? scopes,
  ) {
    final where = <String>[];
    final args = <Object?>[];
    _applyFilters(interpretation, scopes, where, args);
    args.add(_fuzzyScanLimit);

    final candidates = _db.select(
      'SELECT m.*, s.name AS subject_name FROM search_map m '
      'LEFT JOIN subjects s ON s.id = m.subject_id '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'ORDER BY m.occurred_at DESC LIMIT ?',
      args,
    );

    return candidates.where((row) {
      final words = (row['folded'] as String? ?? '').split(' ');
      for (final term in terms) {
        for (final word in words) {
          if (word.isEmpty) continue;
          if (termScore(term, word) >= _fuzzyFloor) return true;
        }
      }
      return false;
    }).toList();
  }

  void _applyFilters(
    SearchInterpretation interpretation,
    Set<SearchScope>? scopes,
    List<String> where,
    List<Object?> args,
  ) {
    if (scopes != null && scopes.isNotEmpty) {
      where.add('m.ref_table IN (${placeholders(scopes.length)})');
      args.addAll(scopes.map((s) => s.table));
    }
    if (interpretation.after != null) {
      where.add('m.occurred_at >= ?');
      args.add(ms(interpretation.after!));
    }
    if (interpretation.before != null) {
      where.add('m.occurred_at <= ?');
      args.add(ms(interpretation.before!));
    }
  }

  /// Title matches beat body matches, exact beats fuzzy, and recent beats old —
  /// but recency never outranks an actual match.
  double _rank(String title, String body, List<String> terms, DateTime occurredAt) {
    if (terms.isEmpty) return 1;

    final foldedTitle = foldDanish(title);
    final foldedBody = foldDanish(body);
    var score = 0.0;

    for (final term in terms) {
      if (foldedTitle.contains(term)) {
        score += 4;
      } else if (foldedBody.contains(term)) {
        score += 2;
      } else {
        var best = 0.0;
        for (final word in foldedTitle.split(RegExp(r'[^a-z0-9]+'))) {
          if (word.isEmpty) continue;
          final s = termScore(term, word);
          if (s > best) best = s;
        }
        score += best * 2;
      }
    }

    final ageDays = DateTime.now().difference(occurredAt).inDays;
    score += ageDays <= 7 ? 0.6 : (ageDays <= 30 ? 0.3 : 0);
    return score;
  }

  /// A window around the first match, so the user sees why a result matched.
  String _snippet(String body, List<String> terms, {int radius = 90}) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= radius * 2) return flat;

    final folded = foldDanish(flat);
    var at = -1;
    for (final term in terms) {
      final i = folded.indexOf(term);
      if (i != -1 && (at == -1 || i < at)) at = i;
    }
    if (at == -1) return '${flat.substring(0, radius * 2).trim()}…';

    final start = (at - radius).clamp(0, flat.length);
    final end = (at + radius).clamp(0, flat.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < flat.length ? '…' : '';
    return '$prefix${flat.substring(start, end).trim()}$suffix';
  }

  @override
  Future<int> rebuild() async {
    transact(_db, () {
      _db.execute('DELETE FROM search_map');
      if (_fts) _db.execute('DELETE FROM search_fts');
    });

    var count = 0;

    for (final row in _db.select('SELECT id, title, body_md, subject_id, updated_at FROM notes')) {
      await index(
        scope: SearchScope.note,
        refId: intOf(row['id']),
        title: row['title'] as String,
        body: row['body_md'] as String? ?? '',
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        occurredAt: timeOf(row['updated_at']),
      );
      count++;
    }

    for (final row in _db.select('SELECT id, title, updated_at FROM conversations')) {
      final id = intOf(row['id']);
      final body = _db
          .select('SELECT content FROM messages WHERE conversation_id = ? ORDER BY id LIMIT 40',
              [id])
          .map((r) => r['content'] as String)
          .join('\n');
      await index(
        scope: SearchScope.conversation,
        refId: id,
        title: row['title'] as String,
        body: body,
        occurredAt: timeOf(row['updated_at']),
      );
      count++;
    }

    for (final row in _db.select('SELECT id, title, subject_id, created_at FROM quizzes')) {
      final id = intOf(row['id']);
      final body = _db
          .select('SELECT prompt FROM quiz_questions WHERE quiz_id = ?', [id])
          .map((r) => r['prompt'] as String)
          .join('\n');
      await index(
        scope: SearchScope.quiz,
        refId: id,
        title: row['title'] as String,
        body: body,
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        occurredAt: timeOf(row['created_at']),
      );
      count++;
    }

    for (final row in _db.select(
        'SELECT id, title, summary, subject_id, started_at FROM timeline_events')) {
      await index(
        scope: SearchScope.timeline,
        refId: intOf(row['id']),
        title: row['title'] as String,
        body: row['summary'] as String? ?? '',
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        occurredAt: timeOf(row['started_at']),
      );
      count++;
    }

    for (final row in _db.select(
        'SELECT id, title, description, subject_id, created_at FROM assignments')) {
      await index(
        scope: SearchScope.assignment,
        refId: intOf(row['id']),
        title: row['title'] as String,
        body: row['description'] as String? ?? '',
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        occurredAt: timeOf(row['created_at']),
      );
      count++;
    }

    for (final row in _db.select(
        'SELECT id, key, value, subject_id, updated_at FROM memories WHERE active = 1')) {
      await index(
        scope: SearchScope.memory,
        refId: intOf(row['id']),
        title: row['value'] as String,
        body: row['key'] as String,
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        occurredAt: timeOf(row['updated_at']),
      );
      count++;
    }

    return count;
  }
}
