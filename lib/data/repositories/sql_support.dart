/// Small conversions every TeenBrain repository needs.
///
/// Times are stored as epoch milliseconds, matching what GlemtDet's v1 tables
/// already do — one convention per database file.
library;

import 'package:sqlite3/sqlite3.dart';

int ms(DateTime t) => t.millisecondsSinceEpoch;
int? msOrNull(DateTime? t) => t?.millisecondsSinceEpoch;

DateTime timeOf(Object? value) => DateTime.fromMillisecondsSinceEpoch(value as int);

DateTime? timeOrNull(Object? value) =>
    value == null ? null : DateTime.fromMillisecondsSinceEpoch(value as int);

bool boolOf(Object? value) => (value as int? ?? 0) != 0;
int boolTo(bool value) => value ? 1 : 0;

double doubleOf(Object? value) => (value as num? ?? 0).toDouble();
int intOf(Object? value) => (value as num? ?? 0).toInt();

/// Midnight local time — the key `daily_activity` is bucketed by.
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// Runs [body] in an immediate transaction, rolling back on any throw.
T transact<T>(Database db, T Function() body) {
  db.execute('BEGIN IMMEDIATE');
  try {
    final result = body();
    db.execute('COMMIT');
    return result;
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

/// `?, ?, ?` for a list of length n. Never build an IN clause by string
/// concatenation of values.
String placeholders(int n) => List.filled(n, '?').join(', ');
