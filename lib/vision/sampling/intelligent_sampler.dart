/// Decides *when* it is worth spending CPU on computer vision.
///
/// The camera delivers frames continuously, but analysing every frame would
/// burn a laptop battery for almost no extra memory. This class turns a cheap
/// per-frame change signal into a small number of well-chosen analyses:
///
///  * never faster than [minInterval] — an upper bound on CPU cost;
///  * whenever the scene changes materially — that is when new things appear;
///  * at least every [idleInterval] — so a static desk still gets recorded;
///  * never on a dark or covered lens;
///  * with exponential backoff while nothing interesting is being found.
///
/// It is deliberately a plain, side-effect-free class so its behaviour can be
/// unit-tested against a synthetic signal stream.
library;

import 'dart:math' as math;

import '../../domain/services/vision_service.dart';

enum SampleDecision {
  /// Not now.
  skip,

  /// The scene changed; analyse because something probably moved.
  changed,

  /// Nothing changed but the idle timer expired; analyse to refresh recency.
  idle,

  /// First frame after start.
  initial,
}

class SamplerConfig {
  const SamplerConfig({
    this.minInterval = const Duration(milliseconds: 1200),
    this.idleInterval = const Duration(seconds: 8),
    this.maxIdleInterval = const Duration(seconds: 40),
    this.changeThreshold = 0.16,
    this.darkThreshold = 0.05,
    this.backoffAfterEmpty = 3,
    this.backoffFactor = 1.6,
  });

  /// Hard floor between two analyses.
  final Duration minInterval;

  /// Baseline "analyse anyway" cadence when the scene is static.
  final Duration idleInterval;

  /// Ceiling the backoff may grow the idle cadence to.
  final Duration maxIdleInterval;

  /// 0..1 change score above which the scene counts as different.
  final double changeThreshold;

  /// Mean luminance below which the frame is not worth looking at.
  final double darkThreshold;

  /// Consecutive empty analyses before backoff kicks in.
  final int backoffAfterEmpty;

  final double backoffFactor;

  /// Battery-friendly preset used when the window is hidden.
  SamplerConfig get background => SamplerConfig(
        minInterval: const Duration(seconds: 3),
        idleInterval: const Duration(seconds: 20),
        maxIdleInterval: const Duration(minutes: 2),
        changeThreshold: changeThreshold + 0.06,
        darkThreshold: darkThreshold,
        backoffAfterEmpty: backoffAfterEmpty,
        backoffFactor: backoffFactor,
      );
}

class IntelligentSampler {
  IntelligentSampler({this.config = const SamplerConfig()});

  /// Swapped at runtime when the app moves between foreground and background.
  SamplerConfig config;
  DateTime? _lastAnalysis;
  int _consecutiveEmpty = 0;

  // Diagnostics, surfaced in the scanner UI so the behaviour is visible.
  int framesSeen = 0;
  int analysesTriggered = 0;
  int framesSkippedDark = 0;
  int framesSkippedRate = 0;

  /// Current idle cadence including backoff.
  Duration get effectiveIdleInterval {
    if (_consecutiveEmpty < config.backoffAfterEmpty) return config.idleInterval;
    final steps = _consecutiveEmpty - config.backoffAfterEmpty + 1;
    final grown = config.idleInterval.inMilliseconds * math.pow(config.backoffFactor, steps);
    final capped = math.min(grown.toDouble(), config.maxIdleInterval.inMilliseconds.toDouble());
    return Duration(milliseconds: capped.round());
  }

  void reset() {
    _lastAnalysis = null;
    _consecutiveEmpty = 0;
  }

  /// Feed one cheap frame signal in; get a decision out.
  SampleDecision evaluate(FrameSignal signal) {
    framesSeen++;

    if (signal.brightness < config.darkThreshold) {
      framesSkippedDark++;
      return SampleDecision.skip;
    }

    final last = _lastAnalysis;
    if (last == null) {
      _lastAnalysis = signal.timestamp;
      analysesTriggered++;
      return SampleDecision.initial;
    }

    final elapsed = signal.timestamp.difference(last);
    if (elapsed < config.minInterval) {
      framesSkippedRate++;
      return SampleDecision.skip;
    }

    if (signal.changeScore >= config.changeThreshold) {
      _lastAnalysis = signal.timestamp;
      analysesTriggered++;
      return SampleDecision.changed;
    }

    if (elapsed >= effectiveIdleInterval) {
      _lastAnalysis = signal.timestamp;
      analysesTriggered++;
      return SampleDecision.idle;
    }

    framesSkippedRate++;
    return SampleDecision.skip;
  }

  /// Report what an analysis produced, so backoff can adapt.
  void reportAnalysis({required bool foundSomething}) {
    if (foundSomething) {
      _consecutiveEmpty = 0;
    } else {
      _consecutiveEmpty++;
    }
  }
}
