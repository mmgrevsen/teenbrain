/// Small, dependency-free string matching used by the search box.
library;

import 'dart:math' as math;

/// Levenshtein distance with an early exit once [maxDistance] is exceeded.
int levenshtein(String a, String b, {int maxDistance = 4}) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    current[0] = i + 1;
    var rowMin = current[0];
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      current[j + 1] = math.min(
        math.min(current[j] + 1, previous[j + 1] + 1),
        previous[j] + cost,
      );
      rowMin = math.min(rowMin, current[j + 1]);
    }
    if (rowMin > maxDistance) return maxDistance + 1;
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// 0..1 similarity. 1 means identical.
double similarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final longest = math.max(a.length, b.length);
  if (longest == 0) return 1;
  final d = levenshtein(a, b, maxDistance: longest);
  return 1 - d / longest;
}

/// How well [term] matches [candidate], allowing prefixes and typos.
/// Returns 0 when there is no plausible match at all.
double termScore(String term, String candidate) {
  if (term.isEmpty || candidate.isEmpty) return 0;
  if (term == candidate) return 1.0;
  if (candidate.startsWith(term)) {
    // "nøgl" → "nøgler" is a strong match; "b" → "briller" is not.
    return term.length < 3 ? 0.0 : 0.92 * (term.length / candidate.length).clamp(0.5, 1.0) + 0.08;
  }
  if (term.startsWith(candidate) && candidate.length >= 4) {
    // The other direction matters just as much in Danish, where the definite
    // form is a suffix: the user types "skrivebordet", the vocabulary holds
    // "skrivebord".
    return 0.9 * (candidate.length / term.length).clamp(0.5, 1.0) + 0.08;
  }
  if (term.length >= 4 && candidate.contains(term)) return 0.7;
  if (term.length >= 4) {
    final sim = similarity(term, candidate);
    if (sim >= 0.72) return sim * 0.85;
  }
  return 0;
}
