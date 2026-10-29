import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/data/db/local_database.dart';
import 'package:glemtdet/data/repositories/sqlite_memory_repository.dart';
import 'package:glemtdet/domain/models/detection.dart';
import 'package:glemtdet/domain/repositories/memory_repository.dart';
import 'package:glemtdet/domain/services/memory_service.dart';
import 'package:glemtdet/domain/services/vision_service.dart';
import 'package:glemtdet/vision/interpretation/taxonomy_object_detection_service.dart';
import 'package:glemtdet/vision/interpretation/taxonomy_scene_recognition_service.dart';
import 'package:glemtdet/vision/sampling/intelligent_sampler.dart';
import 'package:glemtdet/vision/sampling/observation_debouncer.dart';

/// A camera that emits exactly the signals a test asks for. Everything the
/// real macOS camera does beyond this — AVFoundation, the texture, the
/// grayscale hash — is native code that has to be verified by running the app;
/// what *this* covers is the whole Dart pipeline hanging off it.
class FakeCamera implements CameraService {
  final _controller = StreamController<FrameSignal>.broadcast();
  bool started = false;
  int stillsTaken = 0;
  CameraPermission permission = CameraPermission.granted;

  void emit(FrameSignal signal) => _controller.add(signal);

  @override
  bool get isSupported => true;

  @override
  String get unsupportedExplanation => '';

  @override
  bool get isRunning => started;

  @override
  Future<CameraPermission> checkPermission() async => permission;

  @override
  Future<CameraPermission> requestPermission() async => permission;

  @override
  Future<List<CameraDevice>> listDevices() async =>
      const [CameraDevice(id: 'fake', name: 'Fake', isDefault: true)];

  @override
  Future<int?> start({String? deviceId}) async {
    started = true;
    return 7;
  }

  @override
  Future<void> stop() async => started = false;

  @override
  Stream<FrameSignal> get signals => _controller.stream;

  @override
  Future<Uint8List?> captureStill({int maxWidth = 960, double quality = 0.72}) async {
    stillsTaken++;
    return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
  }

  @override
  Future<void> dispose() async => _controller.close();
}

class ScriptedAnalyzer implements FrameAnalyzer {
  ScriptedAnalyzer(this.result);

  VisionFrameAnalysis? result;
  int calls = 0;

  @override
  String get backendId => 'scripted';

  @override
  String get backendDescription => 'Scripted';

  @override
  bool get isAvailable => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<VisionFrameAnalysis?> analyzeCurrentFrame() async {
    calls++;
    return result;
  }

  @override
  Future<List<String>> vocabulary() async => const ['laptop', 'desk'];

  @override
  Future<void> dispose() async {}
}

VisionFrameAnalysis sceneWith(List<String> regionLabels, List<String> frameLabels) =>
    VisionFrameAnalysis(
      capturedAt: DateTime.now(),
      backend: 'scripted',
      frameLabels: [for (final l in frameLabels) RawLabel(identifier: l, confidence: 0.6)],
      regions: [
        for (final l in regionLabels)
          RawRegion(
            bounds: const NormRect(0.3, 0.3, 0.2, 0.2),
            objectness: 0.9,
            labels: [RawLabel(identifier: l, confidence: 0.8)],
          ),
      ],
    );

void main() {
  late Directory scratch;
  late LocalDatabase db;
  late SqliteMemoryRepository repository;
  late FakeCamera camera;
  late ScriptedAnalyzer analyzer;
  late MemoryService service;

  MemoryService build({IntelligentSampler? sampler, ObservationDebouncer? debouncer}) {
    return MemoryService(
      camera: camera,
      analyzer: analyzer,
      objectDetection: TaxonomyObjectDetectionService(),
      sceneRecognition: TaxonomySceneRecognitionService(),
      repository: repository,
      sampler: sampler,
      debouncer: debouncer,
    );
  }

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('glemtdet_service');
    db = LocalDatabase.openInMemory(scratch);
    repository = SqliteMemoryRepository(db);
    camera = FakeCamera();
    analyzer = ScriptedAnalyzer(sceneWith(['laptop', 'headphones'], ['desk']));
    service = build();
  });

  tearDown(() async {
    await service.dispose();
    db.close();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('en analyse bliver til observationer med sted og billede', () async {
    await service.start();
    expect(service.state.status, MemoryStatus.active);
    expect(service.state.textureId, 7);

    await service.analyzeNow();

    final history = await repository.history(const HistoryFilter());
    expect(history.map((o) => o.objectKey).toSet(), {'computer', 'headphones'});
    expect(history.every((o) => o.placeLabel == 'Skrivebord'), isTrue);
    expect(history.every((o) => o.imagePath != null), isTrue);
    // One frame, one still — not one per detected object.
    expect(camera.stillsTaken, 1);
  });

  test('samme scene igen laver ikke nye rækker', () async {
    await service.start();
    await service.analyzeNow();
    await service.analyzeNow();
    await service.analyzeNow();

    final history = await repository.history(const HistoryFilter());
    expect(history, hasLength(2));
    expect(service.state.duplicatesMerged, greaterThan(0));
  });

  test('en flytning bliver gemt som en ny observation', () async {
    await service.start();
    await service.analyzeNow();

    analyzer.result = sceneWith(['headphones'], ['sofa']);
    await service.analyzeNow();

    final headphones = await repository.observationsFor('headphones');
    expect(headphones, hasLength(2));
    expect(headphones.first.placeLabel, 'Sofa');
    expect(headphones.last.placeLabel, 'Skrivebord');
  });

  test('pause skriver ingenting, men analyserer stadig til overlayet', () async {
    await service.start();
    service.setRecording(false);
    expect(service.state.status, MemoryStatus.paused);

    await service.analyzeNow();

    expect(await repository.history(const HistoryFilter()), isEmpty);
    expect(service.state.lastObjects, isNotEmpty);
    expect(service.state.lastScene.label, 'Skrivebord');
  });

  test('billeder kan slås fra uden at miste hukommelsen', () async {
    service.storeImages = false;
    await service.start();
    await service.analyzeNow();

    final history = await repository.history(const HistoryFilter());
    expect(history, isNotEmpty);
    expect(history.every((o) => o.imagePath == null), isTrue);
    expect(camera.stillsTaken, 0);
  });

  test('en scene uden kendte objekter gemmer intet', () async {
    analyzer.result = sceneWith(['volcano'], ['waterfall']);
    await service.start();
    await service.analyzeNow();

    expect(await repository.history(const HistoryFilter()), isEmpty);
    expect(service.state.analysisCount, 1);
  });

  test('kameraafslag giver en forklaring i stedet for en tom skærm', () async {
    camera.permission = CameraPermission.denied;
    await service.start();

    expect(service.state.status, MemoryStatus.error);
    expect(service.state.error, contains('kameraet'));
    expect(camera.started, isFalse);
  });

  test('sampleren styrer hvornår der analyseres', () async {
    await service.start();
    final t0 = DateTime.now();

    // First signal analyses; the next one 200 ms later must not.
    camera.emit(FrameSignal(timestamp: t0, changeScore: 0.5, brightness: 0.5));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    camera.emit(FrameSignal(
      timestamp: t0.add(const Duration(milliseconds: 200)),
      changeScore: 0.9,
      brightness: 0.5,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(analyzer.calls, 1);
  });

  test('stop rydder texturen, så scanneren ikke viser et dødt billede', () async {
    await service.start();
    expect(service.state.textureId, isNotNull);

    await service.stop();
    expect(service.state.textureId, isNull);
    expect(service.state.status, MemoryStatus.idle);
  });

  test('genstart fortsætter hvor hukommelsen slap i stedet for at duplikere', () async {
    await service.start();
    await service.analyzeNow();
    final before = (await repository.history(const HistoryFilter())).length;
    await service.stop();

    // A fresh service against the same database, as after an app restart.
    final second = build();
    await second.start();
    await second.analyzeNow();
    expect((await repository.history(const HistoryFilter())).length, before);
    await second.dispose();
  });
}
