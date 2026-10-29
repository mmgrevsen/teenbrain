import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/domain/services/vision_service.dart';
import 'package:glemtdet/vision/sampling/intelligent_sampler.dart';

FrameSignal signal(DateTime t, {double change = 0, double brightness = 0.5}) =>
    FrameSignal(timestamp: t, changeScore: change, brightness: brightness);

void main() {
  final t0 = DateTime(2026, 9, 4, 12, 0, 0);

  test('første billede analyseres altid', () {
    final sampler = IntelligentSampler();
    expect(sampler.evaluate(signal(t0)), SampleDecision.initial);
  });

  test('mørke billeder springes over uden at koste en analyse', () {
    final sampler = IntelligentSampler();
    final decision = sampler.evaluate(signal(t0, brightness: 0.01));
    expect(decision, SampleDecision.skip);
    expect(sampler.framesSkippedDark, 1);
    expect(sampler.analysesTriggered, 0);
  });

  test('minimumsintervallet holder CPU-forbruget nede', () {
    final sampler = IntelligentSampler();
    sampler.evaluate(signal(t0));
    // A huge scene change 200 ms later must still be refused.
    expect(
      sampler.evaluate(signal(t0.add(const Duration(milliseconds: 200)), change: 0.9)),
      SampleDecision.skip,
    );
  });

  test('markant sceneskift udløser en analyse', () {
    final sampler = IntelligentSampler();
    sampler.evaluate(signal(t0));
    expect(
      sampler.evaluate(signal(t0.add(const Duration(seconds: 2)), change: 0.4)),
      SampleDecision.changed,
    );
  });

  test('statisk scene analyseres stadig på tomgangsintervallet', () {
    final sampler = IntelligentSampler();
    sampler.evaluate(signal(t0));
    expect(
      sampler.evaluate(signal(t0.add(const Duration(seconds: 3)), change: 0.01)),
      SampleDecision.skip,
    );
    expect(
      sampler.evaluate(signal(t0.add(const Duration(seconds: 9)), change: 0.01)),
      SampleDecision.idle,
    );
  });

  test('backoff gør tomgangen langsommere når intet findes', () {
    final sampler = IntelligentSampler();
    final base = sampler.effectiveIdleInterval;
    for (var i = 0; i < 6; i++) {
      sampler.reportAnalysis(foundSomething: false);
    }
    expect(sampler.effectiveIdleInterval, greaterThan(base));
    expect(sampler.effectiveIdleInterval, lessThanOrEqualTo(sampler.config.maxIdleInterval));

    sampler.reportAnalysis(foundSomething: true);
    expect(sampler.effectiveIdleInterval, base);
  });

  test('baggrundsprofilen sampler sjældnere', () {
    const foreground = SamplerConfig();
    final background = foreground.background;
    expect(background.minInterval, greaterThan(foreground.minInterval));
    expect(background.idleInterval, greaterThan(foreground.idleInterval));
    expect(background.changeThreshold, greaterThan(foreground.changeThreshold));
  });

  test('en time med en stillestående scene koster få analyser', () {
    // The whole point of the sampler: a static desk must not generate
    // thousands of Vision passes.
    final sampler = IntelligentSampler();
    var t = t0;
    for (var i = 0; i < 3600 * 2; i++) {
      sampler.evaluate(signal(t, change: 0.01));
      t = t.add(const Duration(milliseconds: 500));
    }
    expect(sampler.framesSeen, 7200);
    expect(sampler.analysesTriggered, lessThan(500));
  });
}
