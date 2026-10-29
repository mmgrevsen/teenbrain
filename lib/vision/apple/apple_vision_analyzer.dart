import 'package:flutter/services.dart';

import '../../domain/models/detection.dart';
import '../../domain/services/vision_service.dart';
import 'apple_channels.dart';

/// Frame analysis backed by Apple's Vision framework, running entirely on the
/// user's Mac. No model is downloaded and no image leaves the process.
///
/// The Swift side runs, per analysed frame:
///
///  1. `VNGenerateObjectnessBasedSaliencyImageRequest` — proposes the regions
///     that contain distinct things;
///  2. `VNClassifyImageRequest` on each proposed region — what that thing is;
///  3. `VNClassifyImageRequest` on the whole frame — the scene, plus any large
///     object that fills the view.
///
/// Saliency plus per-region classification is what gives GlemtDet bounding
/// boxes for a vocabulary far wider than the 80 COCO classes: Vision's
/// taxonomy knows eyeglasses, keys, footwear and earphones, which COCO does
/// not.
class AppleVisionAnalyzer implements FrameAnalyzer {
  AppleVisionAnalyzer({this.maxRegions = 4, this.labelsPerRegion = 6, this.frameLabels = 10});

  static const _method = MethodChannel(AppleChannels.vision);

  /// How many salient regions to classify. Each one costs a crop plus a
  /// classification pass, so this is the main CPU dial.
  final int maxRegions;

  final int labelsPerRegion;
  final int frameLabels;

  bool _available = false;
  List<String>? _vocabulary;

  @override
  String get backendId => 'apple_vision';

  @override
  String get backendDescription =>
      'Apple Vision (lokalt på denne Mac · saliency + billedklassifikation)';

  @override
  bool get isAvailable => _available;

  @override
  Future<void> initialize() async {
    final ok = await _method.invokeMethod<bool>('initialize', {
      'maxRegions': maxRegions,
      'labelsPerRegion': labelsPerRegion,
      'frameLabels': frameLabels,
    });
    _available = ok ?? false;
  }

  @override
  Future<VisionFrameAnalysis?> analyzeCurrentFrame() async {
    final result = await _method.invokeMapMethod<String, Object?>('analyze');
    if (result == null) return null;

    final capturedAt = DateTime.fromMillisecondsSinceEpoch(result['ts'] as int);

    final frame = (result['frameLabels'] as List<Object?>? ?? const [])
        .map((e) => _label(e as Map))
        .toList();

    final regions = (result['regions'] as List<Object?>? ?? const []).map((e) {
      final m = (e as Map).cast<Object?, Object?>();
      return RawRegion(
        bounds: NormRect(
          (m['l'] as num).toDouble(),
          (m['t'] as num).toDouble(),
          (m['w'] as num).toDouble(),
          (m['h'] as num).toDouble(),
        ),
        objectness: (m['objectness'] as num?)?.toDouble(),
        labels: (m['labels'] as List<Object?>? ?? const [])
            .map((l) => _label(l as Map))
            .toList(),
      );
    }).toList();

    return VisionFrameAnalysis(
      capturedAt: capturedAt,
      frameLabels: frame,
      regions: regions,
      backend: backendId,
      analysisMillis: (result['ms'] as num?)?.toInt() ?? 0,
    );
  }

  static RawLabel _label(Map raw) {
    final m = raw.cast<Object?, Object?>();
    return RawLabel(
      identifier: m['id'] as String,
      confidence: (m['c'] as num).toDouble(),
    );
  }

  @override
  Future<List<String>> vocabulary() async {
    return _vocabulary ??= (await _method.invokeListMethod<String>('vocabulary')) ?? const [];
  }

  @override
  Future<void> dispose() async {
    _available = false;
  }
}
