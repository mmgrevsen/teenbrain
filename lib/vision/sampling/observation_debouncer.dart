/// Stops the same object being written to memory over and over.
///
/// A phone lying on a desk will be detected in every single analysis. Without
/// this, ten minutes of scanning produces hundreds of identical rows and a
/// history page nobody can read. The rule GlemtDet uses:
///
///  * the same object in the same place within [cooldown] is *not* a new
///    observation — it refreshes the existing one instead;
///  * the same object in a *different* place always is, because moving is
///    exactly what the user cares about;
///  * a materially better confidence within the cooldown upgrades the stored
///    observation rather than adding a row.
library;

import '../../domain/models/observation.dart';

class DebounceVerdict {
  const DebounceVerdict.store() : action = DebounceAction.store, previousId = null;
  const DebounceVerdict.refresh(this.previousId) : action = DebounceAction.refresh;
  const DebounceVerdict.drop() : action = DebounceAction.drop, previousId = null;

  final DebounceAction action;
  final int? previousId;
}

enum DebounceAction {
  /// Write a new observation.
  store,

  /// Update the timestamp/confidence of an existing one.
  refresh,

  /// Ignore entirely.
  drop,
}

class _Recent {
  _Recent(this.observationId, this.placeKey, this.confidence, this.at);
  int observationId;
  String? placeKey;
  double confidence;
  DateTime at;
}

class ObservationDebouncer {
  ObservationDebouncer({
    this.cooldown = const Duration(seconds: 90),
    this.confidenceUpgradeDelta = 0.12,
  });

  /// Window in which repeat sightings of the same object in the same place are
  /// treated as one continuous observation.
  final Duration cooldown;

  /// How much better a confidence must be before it is worth updating.
  final double confidenceUpgradeDelta;

  final Map<String, _Recent> _recent = {};

  void clear() => _recent.clear();

  /// Seeds state from what is already in the database, so restarting the
  /// scanner does not immediately duplicate everything.
  void seed(Iterable<Observation> latest) {
    for (final o in latest) {
      _recent[o.objectKey] = _Recent(o.id, o.placeKey, o.confidence, o.seenAt);
    }
  }

  DebounceVerdict evaluate(ObservationDraft draft) {
    final prev = _recent[draft.objectKey];
    if (prev == null) return const DebounceVerdict.store();

    final age = draft.seenAt.difference(prev.at);
    if (age >= cooldown) return const DebounceVerdict.store();

    // Moved somewhere else — that is news, regardless of the cooldown.
    if (draft.placeKey != prev.placeKey && draft.placeKey != null) {
      return const DebounceVerdict.store();
    }

    if (draft.confidence >= prev.confidence + confidenceUpgradeDelta) {
      return DebounceVerdict.refresh(prev.observationId);
    }

    // Same thing, same place, no better evidence: just keep it fresh.
    return DebounceVerdict.refresh(prev.observationId);
  }

  /// Records what actually happened so the next verdict is correct.
  void commit(ObservationDraft draft, int observationId) {
    _recent[draft.objectKey] = _Recent(
      observationId,
      draft.placeKey,
      draft.confidence,
      draft.seenAt,
    );
  }
}
