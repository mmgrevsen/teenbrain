import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/detection.dart';
import '../../domain/models/observation.dart';
import '../../domain/repositories/memory_repository.dart';
import '../db/local_database.dart';

/// SQLite-backed implementation of [MemoryRepository].
///
/// Writes are transactional across the three tables that must stay consistent
/// (observations, objects, object_place_stats) so a crash mid-write cannot
/// leave the learned habits disagreeing with the history.
class SqliteMemoryRepository implements MemoryRepository {
  SqliteMemoryRepository(this._local);

  final LocalDatabase _local;
  Database get _db => _local.db;

  @override
  Future<void> initialize() async {}

  // ---------------------------------------------------------------- writes

  @override
  Future<Observation> recordObservation(ObservationDraft draft, {Uint8List? image}) async {
    String? imagePath;
    if (image != null && image.isNotEmpty) {
      imagePath = await _writeFrame(image, draft.seenAt, draft.objectKey);
    }

    final seenAtMs = draft.seenAt.millisecondsSinceEpoch;
    final rawJson = jsonEncode(draft.rawLabels.map((l) => l.toJson()).toList());

    _db.execute('BEGIN IMMEDIATE');
    int id;
    try {
      _db.execute(
        '''
        INSERT INTO objects (key, label, first_seen, last_seen, observation_count, best_confidence)
        VALUES (?, ?, ?, ?, 1, ?)
        ON CONFLICT(key) DO UPDATE SET
          last_seen = MAX(last_seen, excluded.last_seen),
          observation_count = observation_count + 1,
          best_confidence = MAX(best_confidence, excluded.best_confidence),
          label = excluded.label
        ''',
        [draft.objectKey, draft.objectLabel, seenAtMs, seenAtMs, draft.confidence],
      );

      if (draft.placeKey != null) {
        _db.execute(
          '''
          INSERT INTO places (key, label, first_seen, last_seen, observation_count)
          VALUES (?, ?, ?, ?, 1)
          ON CONFLICT(key) DO UPDATE SET
            last_seen = MAX(last_seen, excluded.last_seen),
            observation_count = observation_count + 1,
            label = excluded.label
          ''',
          [draft.placeKey, draft.placeLabel ?? draft.placeKey, seenAtMs, seenAtMs],
        );
        _db.execute(
          '''
          INSERT INTO object_place_stats (object_key, place_key, place_label, count, last_seen)
          VALUES (?, ?, ?, 1, ?)
          ON CONFLICT(object_key, place_key) DO UPDATE SET
            count = count + 1,
            last_seen = MAX(last_seen, excluded.last_seen),
            place_label = excluded.place_label
          ''',
          [draft.objectKey, draft.placeKey, draft.placeLabel ?? draft.placeKey, seenAtMs],
        );
      }

      _db.execute(
        '''
        INSERT INTO observations (
          object_key, object_label, confidence, seen_at,
          place_key, place_label, place_confidence,
          image_path, bbox_l, bbox_t, bbox_w, bbox_h, raw_labels, backend
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          draft.objectKey,
          draft.objectLabel,
          draft.confidence,
          seenAtMs,
          draft.placeKey,
          draft.placeLabel,
          draft.placeConfidence,
          imagePath,
          draft.bounds?.left,
          draft.bounds?.top,
          draft.bounds?.width,
          draft.bounds?.height,
          rawJson,
          draft.backend,
        ],
      );
      id = _db.lastInsertRowId;
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      if (imagePath != null) {
        final f = File(imagePath);
        if (f.existsSync()) f.deleteSync();
      }
      rethrow;
    }

    return Observation(
      id: id,
      objectKey: draft.objectKey,
      objectLabel: draft.objectLabel,
      confidence: draft.confidence,
      seenAt: draft.seenAt,
      placeKey: draft.placeKey,
      placeLabel: draft.placeLabel,
      placeConfidence: draft.placeConfidence,
      imagePath: imagePath,
      bounds: draft.bounds,
      rawLabels: draft.rawLabels,
      backend: draft.backend,
    );
  }

  @override
  Future<void> refreshObservation(
    int id, {
    required DateTime seenAt,
    double? confidence,
    Uint8List? image,
  }) async {
    final row = _db.select('SELECT object_key, image_path, confidence FROM observations WHERE id = ?', [id]);
    if (row.isEmpty) return;
    final objectKey = row.first['object_key'] as String;
    final existingImage = row.first['image_path'] as String?;
    final existingConfidence = (row.first['confidence'] as num).toDouble();

    String? newPath = existingImage;
    if (image != null && image.isNotEmpty) {
      newPath = await _writeFrame(image, seenAt, objectKey);
      if (existingImage != null) {
        final old = File(existingImage);
        if (old.existsSync()) old.deleteSync();
      }
    }

    final effectiveConfidence =
        confidence != null && confidence > existingConfidence ? confidence : existingConfidence;

    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute(
        'UPDATE observations SET seen_at = ?, confidence = ?, image_path = ? WHERE id = ?',
        [seenAt.millisecondsSinceEpoch, effectiveConfidence, newPath, id],
      );
      _db.execute(
        'UPDATE objects SET last_seen = MAX(last_seen, ?), best_confidence = MAX(best_confidence, ?) WHERE key = ?',
        [seenAt.millisecondsSinceEpoch, effectiveConfidence, objectKey],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<String> _writeFrame(Uint8List bytes, DateTime at, String objectKey) async {
    final dir = _local.framesDirectory;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final name = '${at.millisecondsSinceEpoch}_${objectKey}_'
        '${bytes.length.toRadixString(16)}.jpg';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ----------------------------------------------------------------- reads

  Observation _mapObservation(Row row) => Observation(
        id: row['id'] as int,
        objectKey: row['object_key'] as String,
        objectLabel: row['object_label'] as String,
        confidence: (row['confidence'] as num).toDouble(),
        seenAt: DateTime.fromMillisecondsSinceEpoch(row['seen_at'] as int),
        placeKey: row['place_key'] as String?,
        placeLabel: row['place_label'] as String?,
        placeConfidence: (row['place_confidence'] as num?)?.toDouble(),
        imagePath: row['image_path'] as String?,
        bounds: row['bbox_l'] == null
            ? null
            : NormRect(
                (row['bbox_l'] as num).toDouble(),
                (row['bbox_t'] as num).toDouble(),
                (row['bbox_w'] as num).toDouble(),
                (row['bbox_h'] as num).toDouble(),
              ),
        rawLabels: _decodeLabels(row['raw_labels'] as String?),
        backend: row['backend'] as String? ?? 'unknown',
      );

  List<RawLabel> _decodeLabels(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) => RawLabel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Observation?> observationById(int id) async {
    final rows = _db.select('SELECT * FROM observations WHERE id = ?', [id]);
    return rows.isEmpty ? null : _mapObservation(rows.first);
  }

  @override
  Future<List<Observation>> history(HistoryFilter filter) async {
    final where = <String>[];
    final args = <Object?>[];
    if (filter.objectKey != null) {
      where.add('object_key = ?');
      args.add(filter.objectKey);
    }
    if (filter.placeKey != null) {
      where.add('place_key = ?');
      args.add(filter.placeKey);
    }
    if (filter.after != null) {
      where.add('seen_at >= ?');
      args.add(filter.after!.millisecondsSinceEpoch);
    }
    if (filter.before != null) {
      where.add('seen_at <= ?');
      args.add(filter.before!.millisecondsSinceEpoch);
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(filter.limit);
    final rows = _db.select(
      'SELECT * FROM observations $clause ORDER BY seen_at DESC LIMIT ?',
      args,
    );
    return rows.map(_mapObservation).toList();
  }

  @override
  Future<List<Observation>> latestPerObject({int limit = 20}) async {
    final rows = _db.select(
      '''
      SELECT o.* FROM observations o
      JOIN (
        SELECT object_key, MAX(seen_at) AS m FROM observations GROUP BY object_key
      ) latest ON latest.object_key = o.object_key AND latest.m = o.seen_at
      GROUP BY o.object_key
      ORDER BY o.seen_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(_mapObservation).toList();
  }

  @override
  Future<Observation?> lastSeen(String objectKey) async {
    final rows = _db.select(
      'SELECT * FROM observations WHERE object_key = ? ORDER BY seen_at DESC LIMIT 1',
      [objectKey],
    );
    return rows.isEmpty ? null : _mapObservation(rows.first);
  }

  @override
  Future<List<Observation>> observationsFor(String objectKey, {int limit = 50}) async {
    final rows = _db.select(
      'SELECT * FROM observations WHERE object_key = ? ORDER BY seen_at DESC LIMIT ?',
      [objectKey, limit],
    );
    return rows.map(_mapObservation).toList();
  }

  @override
  Future<List<Observation>> around(DateTime at, {Duration window = const Duration(minutes: 3), int? excludeId}) async {
    final from = at.subtract(window).millisecondsSinceEpoch;
    final to = at.add(window).millisecondsSinceEpoch;
    final rows = _db.select(
      '''
      SELECT * FROM observations
      WHERE seen_at BETWEEN ? AND ? AND id != ?
      ORDER BY ABS(seen_at - ?) ASC
      LIMIT 8
      ''',
      [from, to, excludeId ?? -1, at.millisecondsSinceEpoch],
    );
    return rows.map(_mapObservation).toList();
  }

  @override
  Future<List<TrackedObject>> objects() async {
    final rows = _db.select(
      '''
      SELECT
        o.key, o.label, o.first_seen, o.last_seen, o.observation_count, o.best_confidence,
        last.place_key, last.place_label, last.image_path
      FROM objects o
      LEFT JOIN observations last
        ON last.id = (
          SELECT id FROM observations WHERE object_key = o.key ORDER BY seen_at DESC LIMIT 1
        )
      ORDER BY o.last_seen DESC
      ''',
    );
    return rows.map(_mapObject).toList();
  }

  TrackedObject _mapObject(Row row) => TrackedObject(
        key: row['key'] as String,
        label: row['label'] as String,
        firstSeen: DateTime.fromMillisecondsSinceEpoch(row['first_seen'] as int),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(row['last_seen'] as int),
        observationCount: row['observation_count'] as int,
        bestConfidence: (row['best_confidence'] as num?)?.toDouble() ?? 0,
        lastPlaceKey: row['place_key'] as String?,
        lastPlaceLabel: row['place_label'] as String?,
        lastImagePath: row['image_path'] as String?,
      );

  @override
  Future<TrackedObject?> object(String key) async {
    final rows = _db.select(
      '''
      SELECT
        o.key, o.label, o.first_seen, o.last_seen, o.observation_count, o.best_confidence,
        last.place_key, last.place_label, last.image_path
      FROM objects o
      LEFT JOIN observations last
        ON last.id = (
          SELECT id FROM observations WHERE object_key = o.key ORDER BY seen_at DESC LIMIT 1
        )
      WHERE o.key = ?
      ''',
      [key],
    );
    return rows.isEmpty ? null : _mapObject(rows.first);
  }

  @override
  Future<List<TrackedObject>> objectsForMatching() => objects();

  @override
  Future<List<Place>> places() async {
    final rows = _db.select('SELECT * FROM places ORDER BY observation_count DESC');
    return rows
        .map((r) => Place(
              key: r['key'] as String,
              label: r['label'] as String,
              observationCount: r['observation_count'] as int,
              lastSeen: DateTime.fromMillisecondsSinceEpoch(r['last_seen'] as int),
            ))
        .toList();
  }

  @override
  Future<List<PlaceHabit>> habitsFor(String objectKey) async {
    final totalRows = _db.select(
      'SELECT COALESCE(SUM(count), 0) AS total FROM object_place_stats WHERE object_key = ?',
      [objectKey],
    );
    final total = (totalRows.first['total'] as num).toInt();
    if (total == 0) return const [];

    final rows = _db.select(
      'SELECT * FROM object_place_stats WHERE object_key = ? ORDER BY count DESC, last_seen DESC',
      [objectKey],
    );
    return rows
        .map((r) => PlaceHabit(
              objectKey: objectKey,
              placeKey: r['place_key'] as String,
              placeLabel: r['place_label'] as String,
              count: r['count'] as int,
              totalForObject: total,
              lastSeen: DateTime.fromMillisecondsSinceEpoch(r['last_seen'] as int),
            ))
        .toList();
  }

  @override
  Future<StorageStats> stats() async {
    int scalar(String sql) => (_db.select(sql).first.values.first as num?)?.toInt() ?? 0;

    final imageDir = _local.framesDirectory;
    var imageCount = 0;
    var imageBytes = 0;
    if (imageDir.existsSync()) {
      for (final entity in imageDir.listSync()) {
        if (entity is File) {
          imageCount++;
          imageBytes += entity.lengthSync();
        }
      }
    }

    final oldest = _db.select('SELECT MIN(seen_at) AS m FROM observations').first['m'] as int?;

    return StorageStats(
      observationCount: scalar('SELECT COUNT(*) FROM observations'),
      objectCount: scalar('SELECT COUNT(*) FROM objects'),
      placeCount: scalar('SELECT COUNT(*) FROM places'),
      imageCount: imageCount,
      imageBytes: imageBytes,
      databaseBytes: _local.fileSizeBytes,
      oldestObservation: oldest == null ? null : DateTime.fromMillisecondsSinceEpoch(oldest),
    );
  }

  // ------------------------------------------------------------- privacy

  @override
  Future<void> eraseAll() async {
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute('DELETE FROM object_place_stats');
      _db.execute('DELETE FROM observations');
      _db.execute('DELETE FROM objects');
      _db.execute('DELETE FROM places');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    await eraseImages();
    _db.execute('VACUUM');
  }

  @override
  Future<void> eraseImages() async {
    final dir = _local.framesDirectory;
    if (dir.existsSync()) {
      for (final entity in dir.listSync()) {
        if (entity is File) entity.deleteSync();
      }
    }
    _db.execute('UPDATE observations SET image_path = NULL');
  }

  @override
  Future<void> deleteObservation(int id) async {
    final rows = _db.select('SELECT image_path, object_key, place_key FROM observations WHERE id = ?', [id]);
    if (rows.isEmpty) return;
    final imagePath = rows.first['image_path'] as String?;
    final objectKey = rows.first['object_key'] as String;
    final placeKey = rows.first['place_key'] as String?;

    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute('DELETE FROM observations WHERE id = ?', [id]);
      _db.execute(
        'UPDATE objects SET observation_count = MAX(0, observation_count - 1) WHERE key = ?',
        [objectKey],
      );
      if (placeKey != null) {
        _db.execute(
          'UPDATE object_place_stats SET count = MAX(0, count - 1) WHERE object_key = ? AND place_key = ?',
          [objectKey, placeKey],
        );
        _db.execute('DELETE FROM object_place_stats WHERE count <= 0');
      }
      _db.execute('DELETE FROM objects WHERE observation_count <= 0');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    if (imagePath != null) {
      final f = File(imagePath);
      if (f.existsSync()) f.deleteSync();
    }
  }

  @override
  Future<void> deleteObject(String key) async {
    final rows = _db.select('SELECT image_path FROM observations WHERE object_key = ?', [key]);
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute('DELETE FROM object_place_stats WHERE object_key = ?', [key]);
      _db.execute('DELETE FROM observations WHERE object_key = ?', [key]);
      _db.execute('DELETE FROM objects WHERE key = ?', [key]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    for (final r in rows) {
      final path = r['image_path'] as String?;
      if (path == null) continue;
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    }
  }

  @override
  Future<int> pruneBefore(DateTime cutoff) async {
    final ms = cutoff.millisecondsSinceEpoch;
    final doomed = _db.select('SELECT id, image_path FROM observations WHERE seen_at < ?', [ms]);
    if (doomed.isEmpty) return 0;

    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute('DELETE FROM observations WHERE seen_at < ?', [ms]);
      // Recompute aggregates rather than trying to decrement them correctly.
      _db.execute('''
        UPDATE objects SET observation_count =
          (SELECT COUNT(*) FROM observations WHERE object_key = objects.key)
      ''');
      _db.execute('DELETE FROM objects WHERE observation_count = 0');
      _db.execute('''
        UPDATE object_place_stats SET count =
          (SELECT COUNT(*) FROM observations
           WHERE object_key = object_place_stats.object_key
             AND place_key = object_place_stats.place_key)
      ''');
      _db.execute('DELETE FROM object_place_stats WHERE count = 0');
      _db.execute('''
        UPDATE places SET observation_count =
          (SELECT COUNT(*) FROM observations WHERE place_key = places.key)
      ''');
      _db.execute('DELETE FROM places WHERE observation_count = 0');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }

    for (final r in doomed) {
      final path = r['image_path'] as String?;
      if (path == null) continue;
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    }
    return doomed.length;
  }

  @override
  Future<Map<String, dynamic>> exportAll({bool includeImagePaths = true}) async {
    List<Map<String, dynamic>> dump(String table) => _db
        .select('SELECT * FROM $table')
        .map((r) => {for (final k in r.keys) k: r[k]})
        .toList();

    final observations = dump('observations');
    if (!includeImagePaths) {
      for (final o in observations) {
        o.remove('image_path');
      }
    }

    return {
      'app': 'GlemtDet',
      'schema_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'objects': dump('objects'),
      'places': dump('places'),
      'observations': observations,
      'object_place_stats': dump('object_place_stats'),
    };
  }

  @override
  Future<void> close() async => _local.close();
}
