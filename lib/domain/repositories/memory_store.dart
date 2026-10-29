/// Storage for what the app knows about the user.
///
/// Named `MemoryStore` rather than `MemoryRepository` because that name is
/// already taken in this codebase by GlemtDet's visual memory. Different kind
/// of memory, same file, no collision.
library;

import '../models/memory.dart';

abstract class MemoryStore {
  Future<List<Memory>> all({bool activeOnly = false, MemoryKind? kind});
  Future<Memory?> byKey(MemoryKind kind, String key);
  Future<Memory?> byId(int id);

  /// Writes a memory, merging with an existing one on (kind, key).
  ///
  /// Merging is not a blind overwrite: a memory the user stated or edited
  /// themselves is not replaced by something the model inferred. That rule
  /// lives in the implementation, not in each caller.
  Future<Memory> remember(
    MemoryCandidate candidate, {
    required MemorySource source,
    int? subjectId,
    MemoryLink? link,
  });

  Future<Memory> edit(int id, String value);
  Future<void> setActive(int id, bool active);
  Future<void> setPinned(int id, bool pinned);
  Future<void> delete(int id);

  /// Removes every memory. The Privacy page's blunt instrument.
  Future<void> deleteAll({MemoryKind? kind});

  Future<List<MemoryLink>> linksFor(int memoryId);

  /// Candidates for a request, already scored and ordered by relevance.
  ///
  /// The implementation does the scoring locally — no model call — so building
  /// context is free and predictable.
  Future<List<Memory>> ranked({
    required List<String> terms,
    int? subjectId,
    int limit = 40,
  });

  /// Marks memories as having been used, which feeds their future relevance.
  Future<void> markUsed(List<int> ids);

  Future<int> count({bool activeOnly = false});
}
