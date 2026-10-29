/// The engine room: turns a live camera into memory.
///
///     CameraService.signals ─► IntelligentSampler ─► FrameAnalyzer
///        └────────────────────────────────────────────────┘
///                              │
///          ObjectDetectionService + SceneRecognitionService
///                              │
///                     ObservationDebouncer
///                              │
///                      MemoryRepository
///
/// Everything here is platform-agnostic; the only concrete types it touches are
/// the interfaces above. That is what makes the same loop run unchanged on a
/// different vision backend.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../vision/sampling/intelligent_sampler.dart';
import '../../vision/sampling/observation_debouncer.dart';
import '../models/detection.dart';
import '../models/observation.dart';
import '../repositories/memory_repository.dart';
import 'detection_services.dart';
import 'vision_service.dart';

enum MemoryStatus {
  /// Not scanning.
  idle,

  /// Camera starting or permission pending.
  starting,

  /// Running and recording.
  active,

  /// Running but not writing anything down.
  paused,

  /// Something is wrong; see [MemoryState.error].
  error,
}

class MemoryState {
  const MemoryState({
    required this.status,
    this.textureId,
    this.error,
    this.lastAnalysis,
    this.lastObjects = const [],
    this.lastScene = const RecognizedScene.unknown(),
    this.lastAnalysisAt,
    this.analysisCount = 0,
    this.observationCount = 0,
    this.duplicatesMerged = 0,
    this.analysisMillis = 0,
    this.framesSeen = 0,
  });

  final MemoryStatus status;

  /// Flutter texture to render the live preview into, when the backend has one.
  final int? textureId;

  final String? error;

  final VisionFrameAnalysis? lastAnalysis;
  final List<DetectedObject> lastObjects;
  final RecognizedScene lastScene;
  final DateTime? lastAnalysisAt;

  // Live counters shown in the scanner so the sampling behaviour is visible
  // rather than a black box.
  final int analysisCount;
  final int observationCount;
  final int duplicatesMerged;
  final int analysisMillis;
  final int framesSeen;

  bool get isRunning => status == MemoryStatus.active || status == MemoryStatus.paused;

  MemoryState copyWith({
    MemoryStatus? status,
    int? textureId,
    bool clearTexture = false,
    String? error,
    bool clearError = false,
    VisionFrameAnalysis? lastAnalysis,
    List<DetectedObject>? lastObjects,
    RecognizedScene? lastScene,
    DateTime? lastAnalysisAt,
    int? analysisCount,
    int? observationCount,
    int? duplicatesMerged,
    int? analysisMillis,
    int? framesSeen,
  }) =>
      MemoryState(
        status: status ?? this.status,
        textureId: clearTexture ? null : (textureId ?? this.textureId),
        error: clearError ? null : (error ?? this.error),
        lastAnalysis: lastAnalysis ?? this.lastAnalysis,
        lastObjects: lastObjects ?? this.lastObjects,
        lastScene: lastScene ?? this.lastScene,
        lastAnalysisAt: lastAnalysisAt ?? this.lastAnalysisAt,
        analysisCount: analysisCount ?? this.analysisCount,
        observationCount: observationCount ?? this.observationCount,
        duplicatesMerged: duplicatesMerged ?? this.duplicatesMerged,
        analysisMillis: analysisMillis ?? this.analysisMillis,
        framesSeen: framesSeen ?? this.framesSeen,
      );
}

/// Emitted whenever something is written to memory, so the UI can update
/// without polling the database.
class MemoryEvent {
  const MemoryEvent.recorded(this.observation) : merged = false;
  const MemoryEvent.merged(this.observation) : merged = true;
  final Observation observation;
  final bool merged;
}

class MemoryService {
  MemoryService({
    required this._camera,
    required this._analyzer,
    required this._objectDetection,
    required this._sceneRecognition,
    required this._repository,
    IntelligentSampler? sampler,
    ObservationDebouncer? debouncer,
  })  : _sampler = sampler ?? IntelligentSampler(),
        _debouncer = debouncer ?? ObservationDebouncer();

  final CameraService _camera;
  final FrameAnalyzer _analyzer;
  final ObjectDetectionService _objectDetection;
  final SceneRecognitionService _sceneRecognition;
  final MemoryRepository _repository;
  final IntelligentSampler _sampler;
  final ObservationDebouncer _debouncer;

  final _stateController = StreamController<MemoryState>.broadcast();
  final _eventController = StreamController<MemoryEvent>.broadcast();

  StreamSubscription<FrameSignal>? _signalSub;
  bool _analysisInFlight = false;

  MemoryState _state = const MemoryState(status: MemoryStatus.idle);

  MemoryState get state => _state;
  Stream<MemoryState> get states => _stateController.stream;
  Stream<MemoryEvent> get events => _eventController.stream;
  CameraService get camera => _camera;
  FrameAnalyzer get analyzer => _analyzer;
  IntelligentSampler get sampler => _sampler;

  /// When false, analysis still runs for the live overlay but nothing is
  /// written to disk. This is what the "Pause hukommelse" switch controls.
  bool recordingEnabled = true;

  /// Keep a reference frame with each new observation. Turning this off keeps
  /// the textual memory while storing no images at all.
  bool storeImages = true;

  void _emit(MemoryState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  Future<void> start({String? deviceId}) async {
    if (_state.isRunning) return;
    _emit(_state.copyWith(status: MemoryStatus.starting, clearError: true));

    if (!_camera.isSupported) {
      _emit(_state.copyWith(status: MemoryStatus.error, error: _camera.unsupportedExplanation));
      return;
    }

    var permission = await _camera.checkPermission();
    if (permission == CameraPermission.notDetermined) {
      permission = await _camera.requestPermission();
    }
    if (permission != CameraPermission.granted) {
      _emit(_state.copyWith(
        status: MemoryStatus.error,
        error: permission == CameraPermission.restricted
            ? 'Kameraet er spærret af en systempolitik på denne computer.'
            : 'GlemtDet har ikke adgang til kameraet. Giv adgang under '
                'Systemindstillinger ▸ Anonymitet & sikkerhed ▸ Kamera.',
      ));
      return;
    }

    try {
      await _analyzer.initialize();
      final textureId = await _camera.start(deviceId: deviceId);
      _sampler.reset();
      _debouncer.seed(await _repository.latestPerObject(limit: 40));
      _signalSub = _camera.signals.listen(_onSignal, onError: (Object e) {
        _emit(_state.copyWith(status: MemoryStatus.error, error: '$e'));
      });
      _emit(_state.copyWith(
        status: recordingEnabled ? MemoryStatus.active : MemoryStatus.paused,
        textureId: textureId,
        clearError: true,
      ));
    } on CameraException catch (e) {
      _emit(_state.copyWith(status: MemoryStatus.error, error: e.message));
    } catch (e) {
      _emit(_state.copyWith(status: MemoryStatus.error, error: '$e'));
    }
  }

  Future<void> stop() async {
    await _signalSub?.cancel();
    _signalSub = null;
    await _camera.stop();
    _debouncer.clear();
    _emit(_state.copyWith(status: MemoryStatus.idle, clearTexture: true));
  }

  void setRecording(bool enabled) {
    recordingEnabled = enabled;
    if (_state.isRunning) {
      _emit(_state.copyWith(status: enabled ? MemoryStatus.active : MemoryStatus.paused));
    }
  }

  /// Switches the sampler between foreground and background cadences.
  void setBackgroundMode(bool background) {
    const base = SamplerConfig();
    _sampler.config = background ? base.background : base;
  }

  void _onSignal(FrameSignal signal) {
    // An analysis already running means the sampler would only be told to
    // queue work it cannot do, so the frame is dropped outright.
    if (_analysisInFlight) return;
    final decision = _sampler.evaluate(signal);
    _emit(_state.copyWith(framesSeen: _sampler.framesSeen));
    if (decision == SampleDecision.skip) return;
    unawaited(_runAnalysis());
  }

  Future<void> _runAnalysis() async {
    if (_analysisInFlight) return;
    _analysisInFlight = true;
    try {
      final analysis = await _analyzer.analyzeCurrentFrame();
      if (analysis == null) {
        _sampler.reportAnalysis(foundSomething: false);
        return;
      }

      final objects = _objectDetection.detect(analysis);
      final scene = _sceneRecognition.recognize(analysis);

      _emit(_state.copyWith(
        lastAnalysis: analysis,
        lastObjects: objects,
        lastScene: scene,
        lastAnalysisAt: analysis.capturedAt,
        analysisCount: _state.analysisCount + 1,
        analysisMillis: analysis.analysisMillis,
      ));

      _sampler.reportAnalysis(foundSomething: objects.isNotEmpty);
      if (objects.isEmpty || !recordingEnabled) return;

      await _persist(objects, scene, analysis);
    } catch (e) {
      _emit(_state.copyWith(error: '$e'));
    } finally {
      _analysisInFlight = false;
    }
  }

  Future<void> _persist(
    List<DetectedObject> objects,
    RecognizedScene scene,
    VisionFrameAnalysis analysis,
  ) async {
    // Capture the still once and share it across every object in this frame.
    Uint8List? frame;
    var needFrame = false;
    final drafts = <ObservationDraft>[];
    final verdicts = <DebounceVerdict>[];

    for (final object in objects) {
      final draft = ObservationDraft(
        objectKey: object.key,
        objectLabel: object.label,
        confidence: object.confidence,
        seenAt: analysis.capturedAt,
        placeKey: scene.key,
        placeLabel: scene.label,
        placeConfidence: scene.isKnown ? scene.confidence : null,
        bounds: object.bounds,
        rawLabels: object.evidence,
        backend: analysis.backend,
      );
      final verdict = _debouncer.evaluate(draft);
      drafts.add(draft);
      verdicts.add(verdict);
      if (verdict.action == DebounceAction.store) needFrame = true;
    }

    if (needFrame && storeImages) {
      frame = await _camera.captureStill();
    }

    var recorded = 0;
    var merged = 0;
    for (var i = 0; i < drafts.length; i++) {
      final draft = drafts[i];
      final verdict = verdicts[i];
      switch (verdict.action) {
        case DebounceAction.drop:
          break;
        case DebounceAction.store:
          final observation = await _repository.recordObservation(draft, image: frame);
          _debouncer.commit(draft, observation.id);
          recorded++;
          if (!_eventController.isClosed) {
            _eventController.add(MemoryEvent.recorded(observation));
          }
        case DebounceAction.refresh:
          final id = verdict.previousId!;
          await _repository.refreshObservation(
            id,
            seenAt: draft.seenAt,
            confidence: draft.confidence,
          );
          _debouncer.commit(draft, id);
          merged++;
          final updated = await _repository.observationById(id);
          if (updated != null && !_eventController.isClosed) {
            _eventController.add(MemoryEvent.merged(updated));
          }
      }
    }

    _emit(_state.copyWith(
      observationCount: _state.observationCount + recorded,
      duplicatesMerged: _state.duplicatesMerged + merged,
    ));
  }

  /// Forces one analysis right now, ignoring the sampler. Used by the
  /// "Scan nu"-button so the user can always make something happen.
  Future<void> analyzeNow() => _runAnalysis();

  Future<void> dispose() async {
    await _signalSub?.cancel();
    await _camera.dispose();
    await _analyzer.dispose();
    await _stateController.close();
    await _eventController.close();
  }
}
