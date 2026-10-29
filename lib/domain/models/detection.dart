/// Raw output from a vision backend, before it has been interpreted as a
/// memory-worthy observation.
///
/// Nothing in this file knows about Apple Vision, ONNX or any other backend —
/// that is the whole point. Backends produce [VisionFrameAnalysis]; the rest of
/// the app consumes it.
library;

import 'package:meta/meta.dart';

/// A normalised rectangle in image space. Origin is top-left, values in 0..1.
@immutable
class NormRect {
  const NormRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
  double get area => width * height;

  /// Intersection-over-union with [other]. Used to de-duplicate detections of
  /// the same physical object across frames.
  double iou(NormRect other) {
    final ix = (right < other.right ? right : other.right) -
        (left > other.left ? left : other.left);
    final iy = (bottom < other.bottom ? bottom : other.bottom) -
        (top > other.top ? top : other.top);
    if (ix <= 0 || iy <= 0) return 0;
    final inter = ix * iy;
    return inter / (area + other.area - inter);
  }

  Map<String, dynamic> toJson() => {'l': left, 't': top, 'w': width, 'h': height};

  static NormRect? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return NormRect(
      (json['l'] as num).toDouble(),
      (json['t'] as num).toDouble(),
      (json['w'] as num).toDouble(),
      (json['h'] as num).toDouble(),
    );
  }

  @override
  String toString() =>
      'NormRect(${left.toStringAsFixed(2)}, ${top.toStringAsFixed(2)}, '
      '${width.toStringAsFixed(2)}, ${height.toStringAsFixed(2)})';
}

/// A single label produced by a classifier, with the backend's own vocabulary.
@immutable
class RawLabel {
  const RawLabel({required this.identifier, required this.confidence});

  /// Backend-native identifier, e.g. `eyeglasses` from Apple Vision or
  /// `cell phone` from a COCO model. Never shown to the user directly.
  final String identifier;

  /// 0..1
  final double confidence;

  Map<String, dynamic> toJson() => {'id': identifier, 'c': confidence};

  factory RawLabel.fromJson(Map<String, dynamic> json) => RawLabel(
        identifier: json['id'] as String,
        confidence: (json['c'] as num).toDouble(),
      );

  @override
  String toString() => '$identifier(${(confidence * 100).round()}%)';
}

/// A region of the frame that the backend believes contains a distinct thing,
/// together with the labels it assigned to that region.
@immutable
class RawRegion {
  const RawRegion({required this.bounds, required this.labels, this.objectness});

  final NormRect bounds;
  final List<RawLabel> labels;

  /// How confident the backend is that this region contains *something*,
  /// independent of what it is. Null if the backend has no such notion.
  final double? objectness;
}

/// Everything one analysed frame yielded.
@immutable
class VisionFrameAnalysis {
  const VisionFrameAnalysis({
    required this.capturedAt,
    required this.frameLabels,
    required this.regions,
    required this.backend,
    this.analysisMillis = 0,
  });

  const VisionFrameAnalysis.empty(this.capturedAt, this.backend)
      : frameLabels = const [],
        regions = const [],
        analysisMillis = 0;

  final DateTime capturedAt;

  /// Labels for the frame as a whole. Carries most of the *scene* signal
  /// ("desk", "bedroom", "kitchen") as well as large dominant objects.
  final List<RawLabel> frameLabels;

  /// Per-region labels. Carries most of the *object* signal.
  final List<RawRegion> regions;

  /// Identifier of the backend that produced this, e.g. `apple_vision`.
  final String backend;

  final int analysisMillis;

  bool get isEmpty => frameLabels.isEmpty && regions.isEmpty;
}
