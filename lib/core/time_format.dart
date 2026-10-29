/// Danish time phrasing. GlemtDet's answers live or die on these strings, so
/// they are kept in one place and unit-tested.
library;

String _two(int n) => n < 10 ? '0$n' : '$n';

/// "18:42"
String clockOf(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

const _weekdays = [
  'mandag', 'tirsdag', 'onsdag', 'torsdag', 'fredag', 'lørdag', 'søndag',
];

const _months = [
  'januar', 'februar', 'marts', 'april', 'maj', 'juni',
  'juli', 'august', 'september', 'oktober', 'november', 'december',
];

int _daysBetween(DateTime a, DateTime b) {
  final da = DateTime(a.year, a.month, a.day);
  final db = DateTime(b.year, b.month, b.day);
  return db.difference(da).inDays;
}

/// A phrase that can follow a verb: "kl. 18:42", "i går kl. 18:42",
/// "onsdag kl. 18:42", "3. marts kl. 18:42".
String whenPhrase(DateTime t, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final days = _daysBetween(t, ref);
  final clock = 'kl. ${clockOf(t)}';
  if (days == 0) return clock;
  if (days == 1) return 'i går $clock';
  if (days == 2) return 'i forgårs $clock';
  if (days < 7) return '${_weekdays[t.weekday - 1]} $clock';
  return '${t.day}. ${_months[t.month - 1]} $clock';
}

/// Short relative form for lists: "nu", "4 min. siden", "2 t. siden",
/// "i går", "12. aug.".
String shortAgo(DateTime t, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(t);
  if (diff.inSeconds < 45) return 'nu';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min. siden';
  if (diff.inHours < 12) return '${diff.inHours} t. siden';
  final days = _daysBetween(t, ref);
  if (days == 0) return clockOf(t);
  if (days == 1) return 'i går';
  if (days < 7) return _weekdays[t.weekday - 1];
  return '${t.day}. ${_months[t.month - 1].substring(0, 3)}.';
}

/// "i dag", "i går", "onsdag den 3. september"
String dayHeading(DateTime t, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final days = _daysBetween(t, ref);
  if (days == 0) return 'I dag';
  if (days == 1) return 'I går';
  if (days == 2) return 'I forgårs';
  final weekday = _weekdays[t.weekday - 1];
  return '${weekday[0].toUpperCase()}${weekday.substring(1)} den ${t.day}. ${_months[t.month - 1]}';
}

/// "Godmorgen" / "God eftermiddag" / "Godaften" / "Godnat"
String greeting({DateTime? now}) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 5) return 'Godnat';
  if (h < 10) return 'Godmorgen';
  if (h < 12) return 'God formiddag';
  if (h < 18) return 'God eftermiddag';
  if (h < 23) return 'Godaften';
  return 'Godnat';
}

/// How stale an observation is, in words GlemtDet can put in a caveat.
String stalenessCaveat(DateTime t, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(t);
  if (diff.inMinutes < 30) return '';
  if (diff.inHours < 6) return 'Det er den seneste observation, jeg har.';
  if (diff.inDays < 1) return 'Det er et stykke tid siden, så den kan være flyttet.';
  if (diff.inDays < 7) return 'Det er ${diff.inDays == 1 ? 'en dag' : '${diff.inDays} dage'} siden, så den kan sagtens være flyttet.';
  return 'Det er over en uge siden, så jeg vil ikke love at den stadig ligger der.';
}
