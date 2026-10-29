import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

/// Owns the SQLite connection and the on-disk layout.
class LocalDatabase {
  LocalDatabase._(this.db, this.directory);

  final Database db;

  /// Root folder holding the database and the `frames/` image directory.
  final Directory directory;

  Directory get framesDirectory => Directory(p.join(directory.path, 'frames'));

  String get databasePath => p.join(directory.path, 'glemtdet.db');

  static Future<LocalDatabase> open(Directory supportDir) async {
    if (!supportDir.existsSync()) supportDir.createSync(recursive: true);
    final frames = Directory(p.join(supportDir.path, 'frames'));
    if (!frames.existsSync()) frames.createSync(recursive: true);

    final db = sqlite3.open(p.join(supportDir.path, 'glemtdet.db'));
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA synchronous = NORMAL');

    final instance = LocalDatabase._(db, supportDir);
    instance._migrate();
    return instance;
  }

  /// Opens a purely in-memory database. Used by the test suite.
  static LocalDatabase openInMemory(Directory scratchDir) {
    if (!scratchDir.existsSync()) scratchDir.createSync(recursive: true);
    final frames = Directory(p.join(scratchDir.path, 'frames'));
    if (!frames.existsSync()) frames.createSync(recursive: true);
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON');
    final instance = LocalDatabase._(db, scratchDir);
    instance._migrate();
    return instance;
  }

  void _migrate() {
    final current = db.select('PRAGMA user_version').first['user_version'] as int;
    if (current >= kSchemaVersion) return;

    db.execute('BEGIN');
    try {
      for (var version = current; version < kSchemaVersion; version++) {
        for (final statement in kMigrations[version]) {
          db.execute(statement);
        }
      }
      db.execute('PRAGMA user_version = $kSchemaVersion');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  int get fileSizeBytes {
    final f = File(databasePath);
    return f.existsSync() ? f.lengthSync() : 0;
  }

  void close() => db.close();
}
