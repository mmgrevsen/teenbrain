/// Storage contract. The only place the app talks to persistence.
library;

import 'dart:typed_data';

import '../models/observation.dart';

class HistoryFilter {
  const HistoryFilter({this.objectKey, this.placeKey, this.after, this.before, this.limit = 200});
  final String? objectKey;
  final String? placeKey;
  final DateTime? after;
  final DateTime? before;
  final int limit;
}

class StorageStats {
  const StorageStats({
    required this.observationCount,
    required this.objectCount,
    required this.placeCount,
    required this.imageCount,
    required this.imageBytes,
    required this.databaseBytes,
    this.oldestObservation,
  });

  final int observationCount;
  final int objectCount;
  final int placeCount;
  final int imageCount;
  final int imageBytes;
  final int databaseBytes;
  final DateTime? oldestObservation;
}

abstract class MemoryRepository {
  Future<void> initialize();

  /// Writes an observation. [image] is stored on disk and the path recorded;
  /// pass null to record a sighting without keeping a frame.
  Future<Observation> recordObservation(ObservationDraft draft, {Uint8List? image});

  /// Refreshes an existing observation rather than writing a near-duplicate
  /// row. Used by the de-duplicator when the same object is seen again in the
  /// same place moments later.
  Future<void> refreshObservation(
    int id, {
    required DateTime seenAt,
    double? confidence,
    Uint8List? image,
  });

  Future<Observation?> observationById(int id);

  Future<List<Observation>> history(HistoryFilter filter);

  /// Most recent observation per object, newest first.
  Future<List<Observation>> latestPerObject({int limit = 20});

  Future<Observation?> lastSeen(String objectKey);

  Future<List<Observation>> observationsFor(String objectKey, {int limit = 50});

  /// Observations within [window] of [at], excluding [excludeId] — used for
  /// "related sightings" ("din telefon lå der også").
  Future<List<Observation>> around(DateTime at, {Duration window = const Duration(minutes: 3), int? excludeId});

  Future<List<TrackedObject>> objects();

  Future<TrackedObject?> object(String key);

  Future<List<Place>> places();

  /// Learned habits for one object, strongest first.
  Future<List<PlaceHabit>> habitsFor(String objectKey);

  /// All object keys, for fuzzy query matching.
  Future<List<TrackedObject>> objectsForMatching();

  Future<StorageStats> stats();

  // --- Privacy controls -------------------------------------------------

  /// Deletes every observation, object, place and stored image.
  Future<void> eraseAll();

  /// Deletes stored images only; the textual memory survives.
  Future<void> eraseImages();

  Future<void> deleteObservation(int id);

  Future<void> deleteObject(String key);

  /// Removes observations older than [cutoff] and their images.
  Future<int> pruneBefore(DateTime cutoff);

  /// A complete, human-readable export of everything stored.
  Future<Map<String, dynamic>> exportAll({bool includeImagePaths = true});

  Future<void> close();
}
