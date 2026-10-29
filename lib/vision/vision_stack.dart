/// Chooses the vision backend for the platform the app is running on.
///
/// This is the *only* place in GlemtDet that names a concrete backend. Adding
/// Core ML, ONNX Runtime or ML Kit later means adding a branch here and an
/// implementation of the two interfaces — nothing else changes.
library;

import 'dart:io';

import '../domain/services/vision_service.dart';
import 'apple/apple_camera_service.dart';
import 'apple/apple_vision_analyzer.dart';
import 'fallback/unavailable_vision.dart';

class VisionStack {
  const VisionStack({required this.camera, required this.analyzer});

  final CameraService camera;
  final FrameAnalyzer analyzer;

  bool get isLive => camera.isSupported;

  static VisionStack forCurrentPlatform() {
    if (Platform.isMacOS) {
      return VisionStack(camera: AppleCameraService(), analyzer: AppleVisionAnalyzer());
    }
    final explanation = platformVisionExplanation();
    return VisionStack(
      camera: UnavailableCameraService(explanation),
      analyzer: UnavailableFrameAnalyzer(explanation),
    );
  }
}
