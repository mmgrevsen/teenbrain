import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/note.dart';
import '../../domain/models/search.dart';
import '../../domain/repositories/note_repository.dart';
import '../../domain/repositories/search_index.dart';
import '../db/local_database.dart';
import 'sql_support.dart';

class SqliteNoteRepository implements NoteRepository {
  SqliteNoteRepository(this._local, {SearchIndex? searchIndex}) : _search = searchIndex;

  final LocalDatabase _local;

  /// Notes index themselves as they are written. Passing the index in rather
  /// than reaching for a global keeps the repository testable on its own.
  final SearchIndex? _search;

  Database get _db => _local.db;

  @override
  Future<List<Note>> notes({int? subjectId, int? topicId, int limit = 200}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (subjectId != null) {
      where.add('subject_id = ?');
      args.add(subjectId);
    }
    if (topicId != null) {
      where.add('topic_id = ?');
      args.add(topicId);
    }
    args.add(limit);
    final rows = _db.select(
      'SELECT * FROM notes ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'ORDER BY pinned DESC, updated_at DESC LIMIT ?',
      args,
    );
    return rows.map(_map).toList();
  }

  @override
  Future<Note?> note(int id) async {
    final rows = _db.select('SELECT * FROM notes WHERE id = ?', [id]);
    return rows.isEmpty ? null : _map(rows.first);
  }

  @override
  Future<List<Note>> recent({int limit = 5}) async {
    return _db
        .select('SELECT * FROM notes ORDER BY updated_at DESC LIMIT ?', [limit])
        .map(_map)
        .toList();
  }

  @override
  Future<Note> create({
    required String title,
    String bodyMd = '',
    int? subjectId,
    int? topicId,
    NoteSource source = NoteSource.manual,
  }) async {
    final now = ms(DateTime.now());
    _db.execute(
      'INSERT INTO notes (subject_id, topic_id, title, body_md, source, pinned, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, 0, ?, ?)',
      [subjectId, topicId, title.trim(), bodyMd, source.code, now, now],
    );
    final created = (await note(_db.lastInsertRowId))!;
    await _index(created);
    return created;
  }

  @override
  Future<Note> update(Note note) async {
    final now = DateTime.now();
    _db.execute(
      'UPDATE notes SET subject_id = ?, topic_id = ?, title = ?, body_md = ?, '
      'pinned = ?, updated_at = ? WHERE id = ?',
      [
        note.subjectId,
        note.topicId,
        note.title,
        note.bodyMd,
        boolTo(note.pinned),
        ms(now),
        note.id,
      ],
    );
    final saved = (await this.note(note.id))!;
    await _index(saved);
    return saved;
  }

  @override
  Future<void> setPinned(int id, bool pinned) async {
    _db.execute('UPDATE notes SET pinned = ? WHERE id = ?', [boolTo(pinned), id]);
  }

  @override
  Future<void> delete(int id) async {
    _db.execute('DELETE FROM notes WHERE id = ?', [id]);
    await _search?.remove(SearchScope.note, id);
  }

  @override
  Future<String> corpusFor({int? subjectId, int? topicId, int maxChars = 12000}) async {
    final source = await notes(subjectId: subjectId, topicId: topicId, limit: 60);
    final buffer = StringBuffer();
    for (final n in source) {
      final chunk = '## ${n.title}\n${n.bodyMd.trim()}\n\n';
      if (buffer.length + chunk.length > maxChars) break;
      buffer.write(chunk);
    }
    return buffer.toString().trim();
  }

  Future<void> _index(Note note) async {
    await _search?.index(
      scope: SearchScope.note,
      refId: note.id,
      title: note.title,
      body: note.bodyMd,
      subjectId: note.subjectId,
      occurredAt: note.updatedAt,
    );
  }

  Note _map(Row row) => Note(
        id: intOf(row['id']),
        subjectId: row['subject_id'] == null ? null : intOf(row['subject_id']),
        topicId: row['topic_id'] == null ? null : intOf(row['topic_id']),
        title: row['title'] as String,
        bodyMd: row['body_md'] as String? ?? '',
        source: NoteSourceCodec.parse(row['source'] as String?),
        pinned: boolOf(row['pinned']),
        createdAt: timeOf(row['created_at']),
        updatedAt: timeOf(row['updated_at']),
      );
}
