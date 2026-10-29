import 'package:sqlite3/sqlite3.dart';

import '../../domain/models/profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../db/local_database.dart';
import 'sql_support.dart';

class SqliteProfileRepository implements ProfileRepository {
  SqliteProfileRepository(this._local);

  final LocalDatabase _local;
  Database get _db => _local.db;

  @override
  Future<Profile?> read() async {
    final rows = _db.select('SELECT * FROM profile WHERE id = 1');
    if (rows.isEmpty) return null;
    return _map(rows.first);
  }

  @override
  Future<Profile> create({required String displayName, String? gradeLevel}) async {
    final now = DateTime.now();
    _db.execute(
      '''
      INSERT INTO profile (id, display_name, grade_level, created_at, xp, gamification_enabled)
      VALUES (1, ?, ?, ?, 0, 1)
      ON CONFLICT(id) DO UPDATE SET
        display_name = excluded.display_name,
        grade_level  = excluded.grade_level
      ''',
      [displayName, gradeLevel, ms(now)],
    );
    return (await read())!;
  }

  @override
  Future<Profile> update(Profile profile) async {
    _db.execute(
      '''
      UPDATE profile SET
        display_name = ?, grade_level = ?, onboarded_at = ?,
        xp = ?, gamification_enabled = ?
      WHERE id = 1
      ''',
      [
        profile.displayName,
        profile.gradeLevel,
        msOrNull(profile.onboardedAt),
        profile.xp,
        boolTo(profile.gamificationEnabled),
      ],
    );
    return (await read())!;
  }

  @override
  Future<Profile> addXp(int amount) async {
    _db.execute('UPDATE profile SET xp = MAX(0, xp + ?) WHERE id = 1', [amount]);
    final profile = await read();
    if (profile == null) {
      throw StateError('Der er ingen profil at give XP til.');
    }
    return profile;
  }

  Profile _map(Row row) => Profile(
        displayName: row['display_name'] as String,
        gradeLevel: row['grade_level'] as String?,
        createdAt: timeOf(row['created_at']),
        onboardedAt: timeOrNull(row['onboarded_at']),
        xp: intOf(row['xp']),
        gamificationEnabled: boolOf(row['gamification_enabled']),
      );
}
