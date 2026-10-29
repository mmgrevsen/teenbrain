/// Global search across everything the user has made.
library;

import 'package:meta/meta.dart';

/// Which table a hit came from. The UI needs it to know where to navigate.
enum SearchScope { note, conversation, quiz, timeline, assignment, memory }

extension SearchScopeCodec on SearchScope {
  String get table => switch (this) {
        SearchScope.note => 'notes',
        SearchScope.conversation => 'conversations',
        SearchScope.quiz => 'quizzes',
        SearchScope.timeline => 'timeline_events',
        SearchScope.assignment => 'assignments',
        SearchScope.memory => 'memories',
      };

  String get label => switch (this) {
        SearchScope.note => 'Note',
        SearchScope.conversation => 'Samtale',
        SearchScope.quiz => 'Quiz',
        SearchScope.timeline => 'Aktivitet',
        SearchScope.assignment => 'Opgave',
        SearchScope.memory => 'Hukommelse',
      };

  static SearchScope? fromTable(String table) => switch (table) {
        'notes' => SearchScope.note,
        'conversations' => SearchScope.conversation,
        'quizzes' => SearchScope.quiz,
        'timeline_events' => SearchScope.timeline,
        'assignments' => SearchScope.assignment,
        'memories' => SearchScope.memory,
        _ => null,
      };
}

@immutable
class SearchHit {
  const SearchHit({
    required this.scope,
    required this.refId,
    required this.title,
    required this.snippet,
    required this.occurredAt,
    this.subjectId,
    this.subjectName,
    required this.score,
  });

  final SearchScope scope;
  final int refId;
  final String title;

  /// A window of the body around the match, with the match left intact —
  /// highlighting is the UI's job, not the index's.
  final String snippet;

  final DateTime occurredAt;
  final int? subjectId;
  final String? subjectName;
  final double score;
}

/// What a natural-language query turned out to mean.
///
/// "Hvornår lærte jeg om fotosyntese?" is not a keyword search — it is a
/// keyword search plus an intent to answer with a date.
@immutable
class SearchInterpretation {
  const SearchInterpretation({
    required this.terms,
    this.subjectName,
    this.wantsWhen = false,
    this.wantsDifficulty = false,
    this.after,
    this.before,
  });

  const SearchInterpretation.plain(this.terms)
      : subjectName = null,
        wantsWhen = false,
        wantsDifficulty = false,
        after = null,
        before = null;

  final List<String> terms;
  final String? subjectName;

  /// The query asked *when* something happened.
  final bool wantsWhen;

  /// The query asked what the user finds hard.
  final bool wantsDifficulty;

  final DateTime? after;
  final DateTime? before;

  bool get hasTimeWindow => after != null || before != null;
}

/// A search result set, plus the sentence the app puts above it.
@immutable
class SearchOutcome {
  const SearchOutcome({
    required this.hits,
    required this.interpretation,
    this.answer,
  });

  const SearchOutcome.empty()
      : hits = const [],
        interpretation = const SearchInterpretation.plain([]),
        answer = null;

  final List<SearchHit> hits;
  final SearchInterpretation interpretation;

  /// A direct answer when the query asked for one — "Du lærte om fotosyntese
  /// den 14. marts." Null when the hits speak for themselves.
  final String? answer;

  bool get isEmpty => hits.isEmpty && answer == null;
}
