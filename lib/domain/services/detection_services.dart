/// The two interpretation stages between raw vision output and memory:
///
///     FrameAnalyzer ─► ObjectDetectionService ─┐
///                   └► SceneRecognitionService ─┴─► MemoryService
///
/// Both consume [VisionFrameAnalysis] and know nothing about the backend that
/// produced it.
library;

import '../models/detection.dart';

/// One object the app is confident enough to name.
class DetectedObject {
  const DetectedObject({
    required this.key,
    required this.label,
    required this.confidence,
    required this.evidence,
    this.bounds,
  });

  final String key;
  final String label;
  final double confidence;
  final NormRect? bounds;

  /// The backend labels that led here, kept for the detail view.
  final List<RawLabel> evidence;
}

/// The place the frame appears to show.
class RecognizedScene {
  const RecognizedScene({
    required this.key,
    required this.label,
    required this.confidence,
    required this.isSpecific,
    required this.evidence,
    this.alternatives = const [],
  });

  /// No place could be determined. The app says so out loud rather than
  /// inventing a room.
  const RecognizedScene.unknown()
      : key = null,
        label = null,
        confidence = 0,
        isSpecific = false,
        evidence = const [],
        alternatives = const [];

  final String? key;
  final String? label;
  final double confidence;

  /// False for vague places like "Bord" or "Gulv", which are only worth
  /// mentioning with a caveat.
  final bool isSpecific;

  final List<RawLabel> evidence;

  /// Other plausible places, used when the answer needs to admit ambiguity.
  final List<String> alternatives;

  bool get isKnown => key != null;
}

abstract class ObjectDetectionService {
  List<DetectedObject> detect(VisionFrameAnalysis analysis);
}

abstract class SceneRecognitionService {
  RecognizedScene recognize(VisionFrameAnalysis analysis);
}
