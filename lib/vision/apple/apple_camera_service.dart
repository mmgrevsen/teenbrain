import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../domain/services/vision_service.dart';
import 'apple_channels.dart';

/// macOS camera implementation.
///
/// The heavy lifting lives in Swift (AVFoundation): this class only issues
/// commands and forwards the cheap per-frame signal used by the sampler. The
/// live preview is a Flutter texture fed directly from the capture buffer, so
/// no frame ever crosses the platform channel just to be displayed.
class AppleCameraService implements CameraService {
  AppleCameraService();

  static const _method = MethodChannel(AppleChannels.camera);
  static const _events = EventChannel(AppleChannels.frames);

  bool _running = false;
  Stream<FrameSignal>? _signals;

  @override
  bool get isSupported => Platform.isMacOS;

  @override
  String get unsupportedExplanation =>
      'Denne kamerabaggrund er skrevet til macOS med AVFoundation og kører '
      'ikke på ${Platform.operatingSystem}.';

  @override
  bool get isRunning => _running;

  @override
  Future<CameraPermission> checkPermission() async {
    final value = await _method.invokeMethod<String>('permissionStatus');
    return _parsePermission(value);
  }

  @override
  Future<CameraPermission> requestPermission() async {
    final value = await _method.invokeMethod<String>('requestPermission');
    return _parsePermission(value);
  }

  static CameraPermission _parsePermission(String? value) => switch (value) {
        'granted' => CameraPermission.granted,
        'denied' => CameraPermission.denied,
        'restricted' => CameraPermission.restricted,
        _ => CameraPermission.notDetermined,
      };

  @override
  Future<List<CameraDevice>> listDevices() async {
    final raw = await _method.invokeListMethod<Map<Object?, Object?>>('listDevices') ?? [];
    return raw
        .map((m) => CameraDevice(
              id: m['id'] as String,
              name: m['name'] as String,
              isDefault: m['isDefault'] as bool? ?? false,
            ))
        .toList();
  }

  @override
  Future<int?> start({String? deviceId}) async {
    try {
      final result = await _method.invokeMapMethod<String, Object?>('start', {
        'deviceId': ?deviceId,
      });
      _running = true;
      return result?['textureId'] as int?;
    } on PlatformException catch (e) {
      throw CameraException(_reasonFor(e.code), e.message ?? 'Kameraet kunne ikke startes.');
    }
  }

  static CameraUnavailableReason _reasonFor(String code) => switch (code) {
        'permission_denied' => CameraUnavailableReason.permissionDenied,
        'no_device' => CameraUnavailableReason.noDevice,
        'unsupported' => CameraUnavailableReason.platformUnsupported,
        _ => CameraUnavailableReason.failed,
      };

  @override
  Future<void> stop() async {
    if (!_running) return;
    await _method.invokeMethod<void>('stop');
    _running = false;
  }

  @override
  Stream<FrameSignal> get signals {
    return _signals ??= _events.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<Object?, Object?>();
      return FrameSignal(
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
        changeScore: (map['change'] as num).toDouble(),
        brightness: (map['brightness'] as num).toDouble(),
      );
    });
  }

  @override
  Future<Uint8List?> captureStill({int maxWidth = 960, double quality = 0.72}) async {
    if (!_running) return null;
    return _method.invokeMethod<Uint8List>('captureStill', {
      'maxWidth': maxWidth,
      'quality': quality,
    });
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
