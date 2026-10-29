/// The global search index.
///
/// Everything searchable is mirrored into one table as it is written, so search
/// is a single query rather than a fan-out across six tables. The index is a
/// derived artefact: it can be dropped and rebuilt from the source rows.
library;

import '../models/search.dart';

abstract class SearchIndex {
  /// True when the bundled SQLite actually has FTS5. When false, search still
  /// works through a folded-text LIKE scan — slower, never broken. Verified at
  /// startup rather than assumed.
  bool get hasFullTextSearch;

  Future<void> index({
    required SearchScope scope,
    required int refId,
    required String title,
    String body = '',
    int? subjectId,
    required DateTime occurredAt,
  });

  Future<void> remove(SearchScope scope, int refId);

  Future<List<SearchHit>> query(
    SearchInterpretation interpretation, {
    Set<SearchScope>? scopes,
    int limit = 40,
  });

  /// Rebuilds the whole index from the source tables. Used after a restore, or
  /// when the user asks for it on the Privacy page.
  Future<int> rebuild();
}
