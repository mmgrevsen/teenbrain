import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/domain/models/detection.dart';
import 'package:glemtdet/vision/interpretation/taxonomy_object_detection_service.dart';
import 'package:glemtdet/vision/interpretation/taxonomy_scene_recognition_service.dart';

RawLabel label(String id, double c) => RawLabel(identifier: id, confidence: c);

VisionFrameAnalysis analysis({
  List<RawLabel> frame = const [],
  List<RawRegion> regions = const [],
}) =>
    VisionFrameAnalysis(
      capturedAt: DateTime(2026, 9, 4, 18, 42),
      frameLabels: frame,
      regions: regions,
      backend: 'test',
    );

void main() {
  final detector = TaxonomyObjectDetectionService();
  final sceneRecognizer = TaxonomySceneRecognitionService();

  group('objektdetektion', () {
    test('en region med et kendt objekt bliver til et navngivet objekt', () {
      final result = detector.detect(analysis(regions: [
        RawRegion(
          bounds: const NormRect(0.4, 0.5, 0.2, 0.15),
          objectness: 0.9,
          labels: [label('headphones', 0.72), label('plastic', 0.3)],
        ),
      ]));

      expect(result, hasLength(1));
      expect(result.single.key, 'headphones');
      expect(result.single.bounds!.left, 0.4);
      expect(result.single.confidence, greaterThan(0.5));
    });

    test('regionlabels vejer tungere end helbilledlabels', () {
      final fromRegion = detector.detect(analysis(regions: [
        RawRegion(
          bounds: const NormRect(0, 0, 0.2, 0.2),
          objectness: 1.0,
          labels: [label('eyeglasses', 0.6)],
        ),
      ]));
      final fromFrame = detector.detect(analysis(frame: [label('eyeglasses', 0.6)]));

      expect(fromRegion.single.confidence, greaterThan(fromFrame.single.confidence));
    });

    test('samme objekt i to regioner bliver ét resultat', () {
      final result = detector.detect(analysis(regions: [
        RawRegion(
          bounds: const NormRect(0, 0, 0.4, 0.4),
          objectness: 0.5,
          labels: [label('laptop', 0.5)],
        ),
        RawRegion(
          bounds: const NormRect(0.1, 0.1, 0.15, 0.15),
          objectness: 0.9,
          labels: [label('laptop', 0.8)],
        ),
      ]));

      expect(result, hasLength(1));
      expect(result.single.key, 'computer');
      // The tighter, more confident box wins.
      expect(result.single.bounds!.width, 0.15);
      expect(result.single.evidence, hasLength(2));
    });

    test('svage signaler bliver ikke til observationer', () {
      final result = detector.detect(analysis(frame: [label('laptop', 0.1)]));
      expect(result, isEmpty);
    });

    test('ukendte kategorier ignoreres i stilhed', () {
      final result = detector.detect(analysis(
        frame: [label('volcano', 0.99), label('waterfall', 0.95)],
      ));
      expect(result, isEmpty);
    });
  });

  group('scenegenkendelse', () {
    test('finder skrivebordet i helbilledlabels', () {
      final scene = sceneRecognizer.recognize(analysis(
        frame: [label('desk', 0.6), label('computer keyboard', 0.4)],
      ));
      expect(scene.key, 'desk');
      expect(scene.isSpecific, isTrue);
    });

    test('foretrækker et præcist sted frem for et vagt', () {
      final scene = sceneRecognizer.recognize(analysis(
        frame: [label('table', 0.55), label('desk', 0.5)],
      ));
      expect(scene.key, 'desk');
    });

    test('markerer vage steder som upræcise', () {
      final scene = sceneRecognizer.recognize(analysis(frame: [label('table', 0.6)]));
      expect(scene.key, 'table');
      expect(scene.isSpecific, isFalse);
    });

    test('indrømmer når der ikke er noget stedsignal', () {
      final scene = sceneRecognizer.recognize(analysis(frame: [label('volcano', 0.9)]));
      expect(scene.isKnown, isFalse);
      expect(scene.label, isNull);
    });

    test('flere hints om samme sted forstærker hinanden', () {
      final single = sceneRecognizer.recognize(analysis(frame: [label('kitchen', 0.35)]));
      final several = sceneRecognizer.recognize(analysis(
        frame: [label('kitchen', 0.35), label('sink', 0.3), label('stove', 0.25)],
      ));
      expect(several.confidence, greaterThan(single.confidence));
    });

    test('foreslår alternativer når der er tvivl', () {
      final scene = sceneRecognizer.recognize(analysis(
        frame: [label('desk', 0.5), label('sofa', 0.45)],
      ));
      expect(scene.alternatives, isNotEmpty);
    });
  });
}
