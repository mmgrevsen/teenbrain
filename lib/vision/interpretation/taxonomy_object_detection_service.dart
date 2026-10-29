import '../../domain/models/detection.dart';
import '../../domain/services/detection_services.dart';
import '../taxonomy/object_taxonomy.dart';

/// Turns backend labels into named objects using [ObjectTaxonomy].
///
/// Region labels are trusted more than whole-frame labels: a classifier saying
/// "eyeglasses" about a small salient region is much better evidence than the
/// same word about the entire room.
class TaxonomyObjectDetectionService implements ObjectDetectionService {
  TaxonomyObjectDetectionService({
    ObjectTaxonomy? taxonomy,
    this.acceptThreshold = 0.30,
    this.frameLabelPenalty = 0.75,
    this.maxObjectsPerFrame = 6,
  }) : taxonomy = taxonomy ?? ObjectTaxonomy.standard;

  final ObjectTaxonomy taxonomy;

  /// Final score an object must reach to be remembered at all.
  final double acceptThreshold;

  /// Whole-frame labels are weaker evidence than region labels.
  final double frameLabelPenalty;

  final int maxObjectsPerFrame;

  @override
  List<DetectedObject> detect(VisionFrameAnalysis analysis) {
    final best = <String, _Candidate>{};

    void consider(ObjectMatch match, NormRect? bounds, RawLabel raw, double scale) {
      final score = match.confidence * scale;
      final existing = best[match.kind.key];
      if (existing == null) {
        best[match.kind.key] = _Candidate(match.kind.key, match.kind.label, score, bounds, [raw]);
        return;
      }
      existing.evidence.add(raw);
      if (score > existing.score) {
        existing.score = score;
        // Prefer a bounded location over none, and a tighter box over a looser.
        if (bounds != null && (existing.bounds == null || bounds.area < existing.bounds!.area)) {
          existing.bounds = bounds;
        }
      } else if (existing.bounds == null && bounds != null) {
        existing.bounds = bounds;
      }
    }

    for (final region in analysis.regions) {
      for (final label in region.labels) {
        final match = taxonomy.match(label.identifier, label.confidence);
        if (match == null) continue;
        // A region the backend is unsure even contains an object is weaker.
        final objectnessScale = region.objectness == null
            ? 1.0
            : (0.7 + 0.3 * region.objectness!.clamp(0.0, 1.0));
        consider(match, region.bounds, label, objectnessScale);
      }
    }

    for (final label in analysis.frameLabels) {
      final match = taxonomy.match(label.identifier, label.confidence);
      if (match == null) continue;
      consider(match, null, label, frameLabelPenalty);
    }

    final results = best.values.where((c) => c.score >= acceptThreshold).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return results
        .take(maxObjectsPerFrame)
        .map((c) => DetectedObject(
              key: c.key,
              label: c.label,
              confidence: c.score.clamp(0.0, 1.0),
              bounds: c.bounds,
              evidence: List.unmodifiable(c.evidence),
            ))
        .toList();
  }
}

class _Candidate {
  _Candidate(this.key, this.label, this.score, this.bounds, this.evidence);
  final String key;
  final String label;
  double score;
  NormRect? bounds;
  final List<RawLabel> evidence;
}
