import '../../domain/models/detection.dart';
import '../../domain/services/detection_services.dart';
import '../taxonomy/place_taxonomy.dart';

/// Works out where the camera is pointing.
///
/// Scene signal lives mostly in the whole-frame labels — a close-up region of a
/// pair of glasses says nothing about the room. Region labels are still read,
/// but only to catch furniture the frame classifier missed, and at a discount.
class TaxonomySceneRecognitionService implements SceneRecognitionService {
  TaxonomySceneRecognitionService({
    PlaceTaxonomy? taxonomy,
    this.acceptThreshold = 0.20,
    this.regionPenalty = 0.6,
  }) : taxonomy = taxonomy ?? PlaceTaxonomy.standard;

  final PlaceTaxonomy taxonomy;
  final double acceptThreshold;
  final double regionPenalty;

  @override
  RecognizedScene recognize(VisionFrameAnalysis analysis) {
    final scores = <String, _SceneCandidate>{};

    void consider(PlaceMatch match, RawLabel raw, double scale) {
      final score = match.confidence * scale;
      final existing = scores[match.kind.key];
      if (existing == null) {
        scores[match.kind.key] = _SceneCandidate(match.kind, score, [raw]);
      } else {
        existing.evidence.add(raw);
        // Independent labels pointing at the same place reinforce each other,
        // but with diminishing returns so three weak hints never beat one
        // strong one outright.
        existing.score = existing.score + score * 0.45;
      }
    }

    for (final label in analysis.frameLabels) {
      final match = taxonomy.match(label.identifier, label.confidence);
      if (match != null) consider(match, label, 1.0);
    }
    for (final region in analysis.regions) {
      for (final label in region.labels) {
        final match = taxonomy.match(label.identifier, label.confidence);
        if (match != null) consider(match, label, regionPenalty);
      }
    }

    if (scores.isEmpty) return const RecognizedScene.unknown();

    final ranked = scores.values.toList()
      ..sort((a, b) {
        // A specific surface beats a vague one even at slightly lower score;
        // "Skrivebord" is a more useful answer than "Bord".
        final specDelta = _specificityRank(b.kind.specificity) - _specificityRank(a.kind.specificity);
        if (specDelta != 0 && (a.score - b.score).abs() < 0.15) return specDelta;
        return b.score.compareTo(a.score);
      });

    final top = ranked.first;
    if (top.score < acceptThreshold) return const RecognizedScene.unknown();

    return RecognizedScene(
      key: top.kind.key,
      label: top.kind.label,
      confidence: top.score.clamp(0.0, 1.0),
      isSpecific: top.kind.specificity != PlaceSpecificity.vague,
      evidence: List.unmodifiable(top.evidence),
      alternatives: ranked.skip(1).take(2).map((c) => c.kind.label).toList(),
    );
  }

  static int _specificityRank(PlaceSpecificity s) => switch (s) {
        PlaceSpecificity.surface => 2,
        PlaceSpecificity.room => 1,
        PlaceSpecificity.vague => 0,
      };
}

class _SceneCandidate {
  _SceneCandidate(this.kind, this.score, this.evidence);
  final PlaceKind kind;
  double score;
  final List<RawLabel> evidence;
}
