import 'package:sqlite3/sqlite3.dart';

import '../../core/danish.dart';
import '../../core/fuzzy.dart';
import '../../domain/models/memory.dart';
import '../../domain/repositories/memory_store.dart';
import '../db/local_database.dart';
import 'sql_support.dart';

/// SQLite-backed [MemoryStore].
///
/// The interesting part is [ranked]: relevance is scored here, locally, with no
/// model call and no embedding index. That keeps context assembly free, which
/// is what makes it affordable to do on every single request.
class SqliteMemoryStore implements MemoryStore {
  SqliteMemoryStore(this._local);

  final LocalDatabase _local;
  Database get _db => _local.db;

  @override
  Future<List<Memory>> all({bool activeOnly = false, MemoryKind? kind}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (activeOnly) where.add('active = 1');
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind.code);
    }
    final rows = _db.select(
      'SELECT * FROM memories ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'ORDER BY pinned DESC, updated_at DESC',
      args,
    );
    return rows.map(_map).toList();
  }

  @override
  Future<Memory?> byKey(MemoryKind kind, String key) async {
    final rows = _db.select(
      'SELECT * FROM memories WHERE kind = ? AND key = ?',
      [kind.code, key],
    );
    return rows.isEmpty ? null : _map(rows.first);
  }

  @override
  Future<Memory?> byId(int id) async {
    final rows = _db.select('SELECT * FROM memories WHERE id = ?', [id]);
    return rows.isEmpty ? null : _map(rows.first);
  }

  @override
  Future<Memory> remember(
    MemoryCandidate candidate, {
    required MemorySource source,
    int? subjectId,
    MemoryLink? link,
  }) async {
    final now = ms(DateTime.now());
    final existing = await byKey(candidate.kind, candidate.key);

    if (existing != null) {
      // Something the user said outright is not overwritten by something the
      // model guessed. Confidence can still rise; the wording stays theirs.
      final keepValue = existing.source.isAuthoritative && !source.isAuthoritative;

      _db.execute(
        'UPDATE memories SET value = ?, confidence = ?, source = ?, subject_id = ?, '
        'updated_at = ? WHERE id = ?',
        [
          keepValue ? existing.value : candidate.value,
          keepValue
              ? existing.confidence
              : _mergeConfidence(existing.confidence, candidate.confidence),
          keepValue ? existing.source.code : source.code,
          subjectId ?? existing.subjectId,
          now,
          existing.id,
        ],
      );
      if (link != null) _link(existing.id, link);
      return (await byId(existing.id))!;
    }

    _db.execute(
      'INSERT INTO memories '
      '(kind, key, value, confidence, source, subject_id, created_at, updated_at, '
      ' use_count, pinned, active) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 1)',
      [
        candidate.kind.code,
        candidate.key,
        candidate.value,
        candidate.confidence.clamp(0.0, 1.0),
        source.code,
        subjectId,
        now,
        now,
      ],
    );
    final id = _db.lastInsertRowId;
    if (link != null) _link(id, link);
    return (await byId(id))!;
  }

  /// Seeing the same thing twice makes it more certain, but never certain.
  double _mergeConfidence(double existing, double incoming) {
    final merged = existing + (1 - existing) * incoming * 0.5;
    return merged.clamp(0.0, 0.98);
  }

  void _link(int memoryId, MemoryLink link) {
    _db.execute(
      'INSERT OR IGNORE INTO memory_links (memory_id, ref_table, ref_id) VALUES (?, ?, ?)',
      [memoryId, link.refTable, link.refId],
    );
  }

  @override
  Future<Memory> edit(int id, String value) async {
    _db.execute(
      'UPDATE memories SET value = ?, source = ?, confidence = 1.0, updated_at = ? WHERE id = ?',
      [value.trim(), MemorySource.userEdit.code, ms(DateTime.now()), id],
    );
    final memory = await byId(id);
    if (memory == null) throw StateError('Den hukommelse findes ikke længere.');
    return memory;
  }

  @override
  Future<void> setActive(int id, bool active) async {
    _db.execute('UPDATE memories SET active = ? WHERE id = ?', [boolTo(active), id]);
  }

  @override
  Future<void> setPinned(int id, bool pinned) async {
    _db.execute('UPDATE memories SET pinned = ? WHERE id = ?', [boolTo(pinned), id]);
  }

  @override
  Future<void> delete(int id) async {
    _db.execute('DELETE FROM memories WHERE id = ?', [id]);
  }

  @override
  Future<void> deleteAll({MemoryKind? kind}) async {
    if (kind == null) {
      _db.execute('DELETE FROM memories');
    } else {
      _db.execute('DELETE FROM memories WHERE kind = ?', [kind.code]);
    }
  }

  @override
  Future<List<MemoryLink>> linksFor(int memoryId) async {
    return _db
        .select('SELECT ref_table, ref_id FROM memory_links WHERE memory_id = ?', [memoryId])
        .map((r) => MemoryLink(refTable: r['ref_table'] as String, refId: intOf(r['ref_id'])))
        .toList();
  }

  // ------------------------------------------------------------- relevance

  @override
  Future<List<Memory>> ranked({
    required List<String> terms,
    int? subjectId,
    int limit = 40,
  }) async {
    final candidates = await all(activeOnly: true);
    if (candidates.isEmpty) return const [];

    final now = DateTime.now();
    final folded = terms.map(foldDanish).where((t) => t.length > 1).toList();

    final scored = <(double, Memory)>[];
    for (final memory in candidates) {
      scored.add((_score(memory, folded, subjectId, now), memory));
    }

    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.take(limit).map((e) => e.$2).toList();
  }

  /// Four signals, deliberately simple and deliberately explainable:
  /// what the query is about, what subject is in focus, how fresh it is, and
  /// how often it has proved worth including before.
  double _score(Memory memory, List<String> terms, int? subjectId, DateTime now) {
    if (memory.pinned) return 1000;

    var score = 0.0;

    // Kind: preferences and facts describe the user and are almost always
    // worth a line; learning history only matters when asked about.
    score += switch (memory.kind) {
      MemoryKind.preference => 3.0,
      MemoryKind.fact => 2.5,
      MemoryKind.struggle => 1.5,
      MemoryKind.strength => 1.0,
      MemoryKind.learning => 0.5,
    };

    if (terms.isNotEmpty) {
      final haystack = foldDanish('${memory.key} ${memory.value}');
      var best = 0.0;
      for (final term in terms) {
        for (final word in haystack.split(RegExp(r'[^a-z0-9]+'))) {
          if (word.isEmpty) continue;
          final s = termScore(term, word);
          if (s > best) best = s;
        }
      }
      score += best * 6.0;
    }

    if (subjectId != null && memory.subjectId == subjectId) score += 3.0;

    final ageDays = now.difference(memory.updatedAt).inDays;
    score += ageDays <= 1
        ? 1.5
        : ageDays <= 7
            ? 1.0
            : ageDays <= 30
                ? 0.5
                : 0.0;

    // Diminishing returns, so a memory used once does not dominate forever.
    score += memory.useCount == 0 ? 0 : 0.6 * (1 - 1 / (1 + memory.useCount / 5));
    score += memory.confidence;

    return score;
  }

  @override
  Future<void> markUsed(List<int> ids) async {
    if (ids.isEmpty) return;
    _db.execute(
      'UPDATE memories SET use_count = use_count + 1, last_used_at = ? '
      'WHERE id IN (${placeholders(ids.length)})',
      [ms(DateTime.now()), ...ids],
    );
  }

  @override
  Future<int> count({bool activeOnly = false}) async {
    final row = _db
        .select('SELECT COUNT(*) AS n FROM memories ${activeOnly ? 'WHERE active = 1' : ''}')
        .first;
    return intOf(row['n']);
  }

  Memory _map(Row row) => Memory(
        id: intOf(row['id']),
        kind: MemoryKindCodec.parse(row['kind'] as String?),
        key: row['key'] as String,
        value: row['value'] as String,
        confidence: doubleOf(row['confidence']),
        source: MemorySourceCodec.parse(row['source'] as String?),
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        createdAt: timeOf(row['created_at']),
        updatedAt: timeOf(row['updated_at']),
        lastUsedAt: timeOrNull(row['last_used_at']),
        useCount: intOf(row['use_count']),
        pinned: boolOf(row['pinned']),
        active: boolOf(row['active']),
      );
}
