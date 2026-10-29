/// Who the user is, and how far they have come.
library;

import 'package:meta/meta.dart';

@immutable
class Profile {
  const Profile({
    required this.displayName,
    this.gradeLevel,
    required this.createdAt,
    this.onboardedAt,
    this.xp = 0,
    this.gamificationEnabled = true,
  });

  final String displayName;

  /// Free text rather than an enum: "8. klasse", "1.g", "Year 10" — school
  /// systems differ, and the app has no business rejecting the user's answer.
  final String? gradeLevel;

  final DateTime createdAt;
  final DateTime? onboardedAt;
  final int xp;
  final bool gamificationEnabled;

  bool get isOnboarded => onboardedAt != null;

  /// First name only — the greeting says "Godmorgen, Marcus", not the full name.
  String get firstName {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return trimmed;
    final space = trimmed.indexOf(' ');
    return space == -1 ? trimmed : trimmed.substring(0, space);
  }

  Level get level => Level.forXp(xp);

  Profile copyWith({
    String? displayName,
    String? gradeLevel,
    bool clearGradeLevel = false,
    DateTime? onboardedAt,
    int? xp,
    bool? gamificationEnabled,
  }) =>
      Profile(
        displayName: displayName ?? this.displayName,
        gradeLevel: clearGradeLevel ? null : (gradeLevel ?? this.gradeLevel),
        createdAt: createdAt,
        onboardedAt: onboardedAt ?? this.onboardedAt,
        xp: xp ?? this.xp,
        gamificationEnabled: gamificationEnabled ?? this.gamificationEnabled,
      );
}

/// XP → level, with a curve that stays gentle rather than grinding.
///
/// Level n starts at 100·(n−1)·n/2 XP, so the first few levels come quickly and
/// later ones take real work: 0, 100, 300, 600, 1000, 1500 …
@immutable
class Level {
  const Level({required this.number, required this.title, required this.xpIntoLevel, required this.xpForLevel});

  final int number;
  final String title;
  final int xpIntoLevel;
  final int xpForLevel;

  double get progress => xpForLevel == 0 ? 0 : (xpIntoLevel / xpForLevel).clamp(0.0, 1.0);
  int get xpRemaining => xpForLevel - xpIntoLevel;

  static int xpAtStartOf(int level) => 100 * (level - 1) * level ~/ 2;

  static Level forXp(int xp) {
    var n = 1;
    while (xpAtStartOf(n + 1) <= xp) {
      n++;
    }
    final start = xpAtStartOf(n);
    final next = xpAtStartOf(n + 1);
    return Level(
      number: n,
      title: titleFor(n),
      xpIntoLevel: xp - start,
      xpForLevel: next - start,
    );
  }

  /// Deliberately dry. A sixteen-year-old should not be called "Study Wizard".
  static String titleFor(int level) {
    if (level >= 30) return 'Vedholdende';
    if (level >= 20) return 'Rutineret';
    if (level >= 14) return 'Konsekvent';
    if (level >= 9) return 'Stabil';
    if (level >= 5) return 'I gang';
    if (level >= 2) return 'Ny rutine';
    return 'Lige startet';
  }
}
