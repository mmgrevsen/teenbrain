/// Turns a question into something the index can answer.
///
/// Deliberately local and model-free. Search is the one feature that must work
/// on a train with no signal and no API key, so the interpretation is Danish
/// heuristics over the query — stop words, time phrases, and the two question
/// shapes the app can answer directly.
library;

import '../core/danish.dart';
import '../domain/models/search.dart';

class SearchInterpreter {
  const SearchInterpreter({this.subjectNames = const []});

  /// The user's own subjects, so "matematik" in a query can be recognised as a
  /// subject rather than treated as a keyword.
  final List<String> subjectNames;

  SearchInterpretation interpret(String query, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final folded = foldDanish(query);
    final words = folded.split(' ').where((w) => w.isNotEmpty).toList();

    final subject = _subjectIn(words);
    final window = _timeWindow(folded, at);

    final terms = words
        .where((w) => w.length > 2)
        .where((w) => !kStopWords.contains(w))
        .where((w) => !_searchNoise.contains(w))
        .where((w) => subject == null || foldDanish(subject) != w)
        .toList();

    return SearchInterpretation(
      terms: terms,
      subjectName: subject,
      wantsWhen: _asksWhen(folded),
      wantsDifficulty: _asksDifficulty(folded),
      after: window?.after,
      before: window?.before,
    );
  }

  /// "Hvornår lærte jeg om fotosyntese?" wants a date, not a list.
  bool _asksWhen(String folded) =>
      folded.startsWith('hvornaar') || folded.contains(' hvornaar ');

  /// "Hvad havde jeg svært ved i matematik sidste måned?"
  bool _asksDifficulty(String folded) =>
      folded.contains('svaert ved') ||
      folded.contains('svaert') ||
      folded.contains('problemer med') ||
      folded.contains('daarlig til');

  String? _subjectIn(List<String> words) {
    for (final name in subjectNames) {
      final folded = foldDanish(name);
      if (folded.isEmpty) continue;
      for (final word in words) {
        if (word == folded) return name;
      }
      // Multi-word subjects like "fysik kemi" fold to two tokens.
      if (folded.contains(' ') && words.join(' ').contains(folded)) return name;
    }
    return null;
  }

  ({DateTime? after, DateTime? before})? _timeWindow(String folded, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    if (folded.contains('i dag')) {
      return (after: today, before: today.add(const Duration(days: 1)));
    }
    if (folded.contains('i gaar')) {
      final yesterday = today.subtract(const Duration(days: 1));
      return (after: yesterday, before: today);
    }
    if (folded.contains('denne uge') || folded.contains('i denne uge')) {
      return (after: today.subtract(Duration(days: now.weekday - 1)), before: null);
    }
    if (folded.contains('sidste uge') || folded.contains('i sidste uge')) {
      final thisWeek = today.subtract(Duration(days: now.weekday - 1));
      return (after: thisWeek.subtract(const Duration(days: 7)), before: thisWeek);
    }
    if (folded.contains('sidste maaned')) {
      final thisMonth = DateTime(now.year, now.month);
      return (
        after: DateTime(now.year, now.month - 1),
        before: thisMonth,
      );
    }
    if (folded.contains('denne maaned')) {
      return (after: DateTime(now.year, now.month), before: null);
    }
    if (folded.contains('sidste aar')) {
      return (after: DateTime(now.year - 1), before: DateTime(now.year));
    }

    final days = RegExp(r'sidste (\d+) dage').firstMatch(folded);
    if (days != null) {
      final count = int.tryParse(days.group(1)!) ?? 0;
      if (count > 0) return (after: today.subtract(Duration(days: count)), before: null);
    }

    return null;
  }

  /// Words that survive the general stop list but say nothing about content.
  static const _searchNoise = {
    'find', 'vis', 'mine', 'noter', 'note', 'omkring', 'vedr',
    'laerte', 'laert', 'lavede', 'lavet', 'arbejdede', 'arbejdet',
    'havde', 'have', 'skulle', 'ville', 'kunne', 'jeg', 'mig',
  };
}
