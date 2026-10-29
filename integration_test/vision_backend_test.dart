// Verifies the parts of GlemtDet that only exist when the app is really
// running: the native AVFoundation session, the Flutter texture, and Apple's
// Vision framework. A unit test cannot reach any of it.
//
//   flutter test integration_test/vision_backend_test.dart -d macos
//
// The first run asks for camera access. Allow it, or the camera tests will
// report that permission is missing rather than silently passing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/domain/services/vision_service.dart';
import 'package:glemtdet/vision/interpretation/taxonomy_object_detection_service.dart';
import 'package:glemtdet/vision/interpretation/taxonomy_scene_recognition_service.dart';
import 'package:glemtdet/vision/taxonomy/object_taxonomy.dart';
import 'package:glemtdet/vision/taxonomy/place_taxonomy.dart';
import 'package:glemtdet/vision/vision_stack.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late VisionStack stack;

  setUpAll(() {
    stack = VisionStack.forCurrentPlatform();
  });

  tearDownAll(() async {
    await stack.camera.dispose();
    await stack.analyzer.dispose();
  });

  testWidgets('platformen har en rigtig kamerabaggrund', (tester) async {
    expect(stack.camera.isSupported, isTrue,
        reason: 'Denne test skal køre på en platform med en kamerabaggrund.');
    expect(Platform.isMacOS, isTrue);
  });

  testWidgets('Vision melder sit ordforråd, og taksonomien rammer det', (tester) async {
    await stack.analyzer.initialize();
    final vocabulary = await stack.analyzer.vocabulary();

    // Written out so the Danish taxonomy can be maintained against the real
    // vocabulary instead of guesses about what Vision might call things.
    final dump = File('build/vision_vocabulary.txt');
    dump.parent.createSync(recursive: true);
    dump.writeAsStringSync(vocabulary.join('\n'));
    // ignore: avoid_print
    print('Vision kender ${vocabulary.length} kategorier — skrevet til ${dump.path}');
    expect(vocabulary, isNotEmpty,
        reason: 'VNClassifyImageRequest.knownClassifications gav ingenting.');

    final objects = ObjectTaxonomy.standard;
    final missing = <String>[];
    for (final kind in objects.kinds) {
      final hits = objects.coverageFor(kind.key, vocabulary);
      // ignore: avoid_print
      print('  ${kind.label.padRight(12)} ${hits.length} labels'
          '${hits.isEmpty ? '  ← INGEN DÆKNING' : ': ${hits.take(4).join(', ')}'}');
      if (hits.isEmpty) missing.add(kind.label);
    }

    final places = PlaceTaxonomy.standard;
    final missingPlaces = <String>[];
    for (final kind in places.kinds) {
      final hits = vocabulary.where((l) => places.match(l, 1.0)?.kind.key == kind.key).toList();
      // ignore: avoid_print
      print('  [sted] ${kind.label.padRight(14)} ${hits.length} labels'
          '${hits.isEmpty ? '  ← INGEN DÆKNING' : ': ${hits.take(4).join(', ')}'}');
      if (hits.isEmpty) missingPlaces.add(kind.label);
    }

    // ignore: avoid_print
    print('Objekttyper uden dækning: ${missing.isEmpty ? 'ingen' : missing.join(', ')}');
    // ignore: avoid_print
    print('Steder uden dækning: ${missingPlaces.isEmpty ? 'ingen' : missingPlaces.join(', ')}');

    // The headline objects from the brief have to be reachable, or the app
    // cannot do the job it promises.
    for (final key in ['phone', 'computer', 'glasses', 'bag', 'book', 'bottle', 'shoes']) {
      expect(objects.coverageFor(key, vocabulary), isNotEmpty,
          reason: 'Vision har ingen label der kan blive til "$key".');
    }
  });

  testWidgets('kameraet kan findes, startes og levere billeder', (tester) async {
    final permission = await stack.camera.checkPermission();
    // ignore: avoid_print
    print('Kameratilladelse: $permission');
    if (permission != CameraPermission.granted) {
      final asked = await stack.camera.requestPermission();
      // ignore: avoid_print
      print('Efter forespørgsel: $asked');
      expect(asked, CameraPermission.granted,
          reason: 'Giv GlemtDet adgang til kameraet og kør testen igen.');
    }

    final devices = await stack.camera.listDevices();
    // ignore: avoid_print
    print('Kameraer: ${devices.map((d) => d.name).join(', ')}');
    expect(devices, isNotEmpty);

    final signals = <FrameSignal>[];
    final subscription = stack.camera.signals.listen(signals.add);

    final textureId = await stack.camera.start();
    // ignore: avoid_print
    print('Texture id: $textureId');
    expect(textureId, isNotNull);
    expect(textureId, greaterThanOrEqualTo(0));

    // The signal stream is throttled to ~2.5 Hz natively.
    await Future<void>.delayed(const Duration(seconds: 3));
    await subscription.cancel();

    // ignore: avoid_print
    print('Modtog ${signals.length} billedsignaler.');
    expect(signals, isNotEmpty, reason: 'Kameraet leverede ingen billeder.');
    for (final s in signals) {
      expect(s.changeScore, inInclusiveRange(0.0, 1.0));
      expect(s.brightness, inInclusiveRange(0.0, 1.0));
    }
    // ignore: avoid_print
    print('Lysstyrke: ${signals.last.brightness.toStringAsFixed(3)}, '
        'ændring: ${signals.last.changeScore.toStringAsFixed(3)}');
  });

  testWidgets('Vision analyserer et rigtigt billede', (tester) async {
    if (!stack.camera.isRunning) {
      await stack.camera.start();
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    final analysis = await stack.analyzer.analyzeCurrentFrame();
    expect(analysis, isNotNull, reason: 'Der var intet billede at analysere.');

    // ignore: avoid_print
    print('Analyse tog ${analysis!.analysisMillis} ms, '
        '${analysis.frameLabels.length} helbilledlabels, '
        '${analysis.regions.length} regioner.');
    for (final l in analysis.frameLabels.take(8)) {
      // ignore: avoid_print
      print('  billede: ${l.identifier} ${(l.confidence * 100).toStringAsFixed(1)}%');
    }
    for (final r in analysis.regions) {
      // ignore: avoid_print
      print('  region ${r.bounds} objectness=${r.objectness?.toStringAsFixed(2)}: '
          '${r.labels.take(3).map((l) => l.identifier).join(', ')}');
      expect(r.bounds.left, inInclusiveRange(-0.01, 1.01));
      expect(r.bounds.top, inInclusiveRange(-0.01, 1.01));
    }

    expect(analysis.frameLabels, isNotEmpty,
        reason: 'VNClassifyImageRequest gav ingen labels for et rigtigt billede.');
    expect(analysis.analysisMillis, lessThan(4000),
        reason: 'En analyse må ikke tage flere sekunder.');

    final objects = TaxonomyObjectDetectionService().detect(analysis);
    final scene = TaxonomySceneRecognitionService().recognize(analysis);
    // ignore: avoid_print
    print('Genkendte objekter: '
        '${objects.isEmpty ? 'ingen' : objects.map((o) => '${o.label} '
            '${(o.confidence * 100).round()}%').join(', ')}');
    // ignore: avoid_print
    print('Genkendt sted: ${scene.isKnown ? '${scene.label} '
        '${(scene.confidence * 100).round()}%' : 'ukendt'}');
  });

  testWidgets('et referencebillede kan gemmes som JPEG', (tester) async {
    if (!stack.camera.isRunning) {
      await stack.camera.start();
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    final bytes = await stack.camera.captureStill(maxWidth: 640);
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(1000));
    // JPEG magic number — proves it is a real image, not an empty buffer.
    expect(bytes[0], 0xFF);
    expect(bytes[1], 0xD8);
    // ignore: avoid_print
    print('Referencebillede: ${(bytes.length / 1024).toStringAsFixed(1)} KB');

    await stack.camera.stop();
  });
}
