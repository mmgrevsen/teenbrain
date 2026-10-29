/// Abstractions the rest of GlemtDet programs against.
///
///     CameraService  ──┐
///                      ├─► FrameAnalyzer ─► MemoryService ─► MemoryRepository
///     (platform impl) ─┘
///
/// No feature code may import anything from `lib/vision/apple/` or any other
/// concrete backend. Swapping Apple Vision for ONNX, Core ML or ML Kit means
/// providing a different implementation of these interfaces and nothing else.
library;

import 'dart:typed_data';

import '../models/detection.dart';

/// Why a camera is unavailable, so the UI can say something true instead of
/// spinning forever.
enum CameraUnavailableReason {
  permissionDenied,
  noDevice,
  platformUnsupported,
  failed,
}

class CameraException implements Exception {
  CameraException(this.reason, this.message);
  final CameraUnavailableReason reason;
  final String message;
  @override
  String toString() => 'CameraException($reason): $message';
}

enum CameraPermission { granted, denied, notDetermined, restricted }

class CameraDevice {
  const CameraDevice({required this.id, required this.name, this.isDefault = false});
  final String id;
  final String name;
  final bool isDefault;
}

/// A live camera feed. Implementations own the OS capture session.
abstract class CameraService {
  /// Whether this platform build has a working camera implementation at all.
  bool get isSupported;

  /// Human-readable explanation used when [isSupported] is false.
  String get unsupportedExplanation;

  Future<CameraPermission> checkPermission();

  /// May show an OS prompt. Returns the resulting status.
  Future<CameraPermission> requestPermission();

  Future<List<CameraDevice>> listDevices();

  /// Starts capture. Returns a Flutter texture id the UI can render, or null
  /// if this backend has no texture-based preview.
  Future<int?> start({String? deviceId});

  Future<void> stop();

  bool get isRunning;

  /// Emits a cheap per-frame signal used by the sampler to decide *when* to
  /// spend CPU on a real analysis. Must be far cheaper than [FrameAnalyzer].
  Stream<FrameSignal> get signals;

  /// JPEG bytes of the most recent frame, for storing a reference image.
  Future<Uint8List?> captureStill({int maxWidth = 960, double quality = 0.72});

  Future<void> dispose();
}

/// A lightweight heartbeat from the capture pipeline.
class FrameSignal {
  const FrameSignal({
    required this.timestamp,
    required this.changeScore,
    required this.brightness,
  });

  final DateTime timestamp;

  /// 0..1 — how much the frame differs from the last frame that was actually
  /// analysed. Computed from a tiny grayscale hash, not a full comparison.
  final double changeScore;

  /// 0..1 mean luminance. A dark frame (lens covered, screen off) is not worth
  /// analysing.
  final double brightness;
}

/// Runs computer vision on the current frame. Deliberately *pull-based*: the
/// sampler decides when, so CPU cost stays under the app's control.
abstract class FrameAnalyzer {
  /// Stable backend identifier stored alongside every observation.
  String get backendId;

  /// Shown in Settings so the user can see what is actually running.
  String get backendDescription;

  bool get isAvailable;

  Future<void> initialize();

  /// Analyses the most recent captured frame. Returns null if no frame is
  /// ready. Must never throw for ordinary "nothing found" cases.
  Future<VisionFrameAnalysis?> analyzeCurrentFrame();

  /// The backend's full label vocabulary, used to build and verify the
  /// taxonomy mapping. Empty if the backend cannot report it.
  Future<List<String>> vocabulary();

  Future<void> dispose();
}
