/// The things GlemtDet actually remembers.
library;

import 'package:meta/meta.dart';

import 'detection.dart';

/// How sure GlemtDet is about *where* an object was, expressed as a
/// user-facing honesty level rather than a bare number.
enum PlaceCertainty {
  /// A concrete place was recognised with good confidence.
  confident,

  /// A surface/place type was recognised but could be one of several rooms.
  approximate,

  /// No place signal at all.
  unknown;

  static PlaceCertainty fromConfidence(double? c) {
    if (c == null) return PlaceCertainty.unknown;
    if (c >= 0.55) return PlaceCertainty.confident;
    if (c >= 0.25) return PlaceCertainty.approximate;
    return PlaceCertainty.unknown;
  }
}

/// One remembered sighting of one object at one moment.
@immutable
class Observation {
  const Observation({
    required this.id,
    required this.objectKey,
    required this.objectLabel,
    required this.confidence,
    required this.seenAt,
    this.placeKey,
    this.placeLabel,
    this.placeConfidence,
    this.imagePath,
    this.bounds,
    this.rawLabels = const [],
    this.backend = 'unknown',
  });

  final int id;

  /// Canonical, language-independent object key, e.g. `airpods`.
  final String objectKey;

  /// Danish display name, e.g. `AirPods`.
  final String objectLabel;

  /// 0..1
  final double confidence;

  final DateTime seenAt;

  final String? placeKey;
  final String? placeLabel;
  final double? placeConfidence;

  /// Absolute path to the stored reference frame, if one was kept.
  final String? imagePath;

  /// Where in the reference frame the object was.
  final NormRect? bounds;

  /// The backend-native labels behind this observation, kept so the reasoning
  /// stays inspectable and so a future backend swap can be debugged.
  final List<RawLabel> rawLabels;

  final String backend;

  PlaceCertainty get placeCertainty =>
      placeKey == null ? PlaceCertainty.unknown : PlaceCertainty.fromConfidence(placeConfidence);

  bool get hasImage => imagePath != null;

  Observation copyWith({String? imagePath}) => Observation(
        id: id,
        objectKey: objectKey,
        objectLabel: objectLabel,
        confidence: confidence,
        seenAt: seenAt,
        placeKey: placeKey,
        placeLabel: placeLabel,
        placeConfidence: placeConfidence,
        imagePath: imagePath ?? this.imagePath,
        bounds: bounds,
        rawLabels: rawLabels,
        backend: backend,
      );
}

/// A draft observation that has not been written to the database yet.
@immutable
class ObservationDraft {
  const ObservationDraft({
    required this.objectKey,
    required this.objectLabel,
    required this.confidence,
    required this.seenAt,
    this.placeKey,
    this.placeLabel,
    this.placeConfidence,
    this.bounds,
    this.rawLabels = const [],
    this.backend = 'unknown',
  });

  final String objectKey;
  final String objectLabel;
  final double confidence;
  final DateTime seenAt;
  final String? placeKey;
  final String? placeLabel;
  final double? placeConfidence;
  final NormRect? bounds;
  final List<RawLabel> rawLabels;
  final String backend;
}

/// An object GlemtDet believes the user owns, aggregated across observations.
@immutable
class TrackedObject {
  const TrackedObject({
    required this.key,
    required this.label,
    required this.firstSeen,
    required this.lastSeen,
    required this.observationCount,
    this.lastPlaceKey,
    this.lastPlaceLabel,
    this.lastImagePath,
    this.bestConfidence = 0,
  });

  final String key;
  final String label;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int observationCount;
  final String? lastPlaceKey;
  final String? lastPlaceLabel;
  final String? lastImagePath;
  final double bestConfidence;
}

/// A place GlemtDet has learned about.
@immutable
class Place {
  const Place({
    required this.key,
    required this.label,
    required this.observationCount,
    required this.lastSeen,
  });

  final String key;
  final String label;
  final int observationCount;
  final DateTime lastSeen;
}

/// "Your AirPods are usually on the desk." — the learned habit behind
/// GlemtDet's long-term memory.
@immutable
class PlaceHabit {
  const PlaceHabit({
    required this.objectKey,
    required this.placeKey,
    required this.placeLabel,
    required this.count,
    required this.totalForObject,
    required this.lastSeen,
  });

  final String objectKey;
  final String placeKey;
  final String placeLabel;
  final int count;
  final int totalForObject;
  final DateTime lastSeen;

  /// Share of this object's placed observations that happened here, 0..1.
  double get share => totalForObject == 0 ? 0 : count / totalForObject;

  /// Only worth telling the user about once there is a real pattern.
  bool get isStrong => count >= 3 && share >= 0.4;
}
