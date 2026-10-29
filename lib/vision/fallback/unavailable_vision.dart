/// What runs on a platform GlemtDet does not yet have a verified vision
/// backend for.
///
/// These deliberately do nothing rather than pretending. Everything else in
/// the app — history, objects, search, answers, privacy controls — works
/// normally against whatever is already in the database; only live capture is
/// missing, and the UI says exactly that.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/models/detection.dart';
import '../../domain/services/vision_service.dart';

class UnavailableCameraService implements CameraService {
  UnavailableCameraService(this.explanation);

  final String explanation;

  @override
  bool get isSupported => false;

  @override
  String get unsupportedExplanation => explanation;

  @override
  bool get isRunning => false;

  @override
  Future<CameraPermission> checkPermission() async => CameraPermission.denied;

  @override
  Future<CameraPermission> requestPermission() async => CameraPermission.denied;

  @override
  Future<List<CameraDevice>> listDevices() async => const [];

  @override
  Future<int?> start({String? deviceId}) async =>
      throw CameraException(CameraUnavailableReason.platformUnsupported, explanation);

  @override
  Future<void> stop() async {}

  @override
  Stream<FrameSignal> get signals => const Stream<FrameSignal>.empty();

  @override
  Future<Uint8List?> captureStill({int maxWidth = 960, double quality = 0.72}) async => null;

  @override
  Future<void> dispose() async {}
}

class UnavailableFrameAnalyzer implements FrameAnalyzer {
  UnavailableFrameAnalyzer(this.explanation);

  final String explanation;

  @override
  String get backendId => 'unavailable';

  @override
  String get backendDescription => explanation;

  @override
  bool get isAvailable => false;

  @override
  Future<void> initialize() async {}

  @override
  Future<VisionFrameAnalysis?> analyzeCurrentFrame() async => null;

  @override
  Future<List<String>> vocabulary() async => const [];

  @override
  Future<void> dispose() async {}
}

/// The honest explanation for the current platform.
String platformVisionExplanation() {
  if (Platform.isWindows) {
    return 'Live-scanning er endnu ikke tilgængelig på Windows. '
        'Kamera- og AI-laget er bygget som udskiftelige moduler, men '
        'Windows-implementeringen (camera_windows + ONNX Runtime) er ikke '
        'færdigbygget og verificeret endnu. Alt andet i GlemtDet virker: '
        'historik, objekter, søgning og databehandling.';
  }
  if (Platform.isLinux) {
    return 'Live-scanning er ikke understøttet på Linux i denne version.';
  }
  return 'Denne platform har ingen verificeret kamera- og AI-baggrund endnu.';
}
