import '../models/profile.dart';

/// The single user of this app. There is exactly one row, and it may not exist
/// yet — onboarding is what creates it.
abstract class ProfileRepository {
  Future<Profile?> read();

  /// Creates the profile row. Called once, at the end of onboarding.
  Future<Profile> create({required String displayName, String? gradeLevel});

  Future<Profile> update(Profile profile);

  /// Adds XP and returns the profile afterwards, so the caller can tell whether
  /// the level changed without reading twice.
  Future<Profile> addXp(int amount);
}
