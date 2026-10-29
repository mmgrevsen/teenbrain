/// Apple's on-device speech recogniser, reached through the app's own native
/// layer (`macos/Runner/GlemtDet/SpeechTranscriber.swift`).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/services/transcriber.dart';

class AppleTranscriber implements Transcriber {
  AppleTranscriber();

  static const _methods = MethodChannel('dk.glemtdet/speech');
  static const _events = EventChannel('dk.glemtdet/transcript');

  final StreamController<TranscriptSegment> _segments =
      StreamController<TranscriptSegment>.broadcast();

  StreamSubscription<dynamic>? _native;
  bool _running = false;

  @override
  bool get isSupported => true;

  @override
  String get unsupportedExplanation => '';

  @override
  String get backendId => 'apple_speech';

  @override
  String get backendLabel => 'macOS\' egen talegenkendelse';

  @override
  bool get isOnDevice => true;

  @override
  bool get isRunning => _running;

  @override
  Stream<TranscriptSegment> get segments => _segments.stream;

  @override
  Future<TranscriberAccess> checkPermission() => _access('speechPermissionStatus');

  @override
  Future<TranscriberAccess> requestPermission() => _access('speechRequestPermission');

  Future<TranscriberAccess> _access(String method) async {
    try {
      final raw = await _methods.invokeMapMethod<String, String>(method);
      return TranscriberAccess(
        microphone: _permission(raw?['microphone']),
        speech: _permission(raw?['speech']),
      );
    } on PlatformException catch (e) {
      debugPrint('Kunne ikke læse mikrofon-tilladelser: ${e.message}');
      return const TranscriberAccess(
        microphone: TranscriberPermission.denied,
        speech: TranscriberPermission.denied,
      );
    } on MissingPluginException {
      // Running under `flutter test`, where there is no platform side.
      return const TranscriberAccess(
        microphone: TranscriberPermission.notDetermined,
        speech: TranscriberPermission.notDetermined,
      );
    }
  }

  static TranscriberPermission _permission(String? code) => switch (code) {
        'granted' => TranscriberPermission.granted,
        'restricted' => TranscriberPermission.restricted,
        'notDetermined' => TranscriberPermission.notDetermined,
        _ => TranscriberPermission.denied,
      };

  @override
  Future<void> start({String localeId = 'da-DK'}) async {
    if (_running) return;

    // Subscribe before starting, so the first segment cannot arrive before
    // there is anything listening for it.
    _native ??= _events.receiveBroadcastStream().listen(
          _onNativeEvent,
          onError: (Object error) {
            _running = false;
            _segments.addError(
              TranscriberException(TranscriberUnavailable.failed, '$error'),
            );
          },
        );

    try {
      await _methods.invokeMethod<bool>('speechStart', {'localeId': localeId});
      _running = true;
    } on PlatformException catch (e) {
      _running = false;
      throw TranscriberException(
        _reason(e.code),
        e.message ?? 'Kunne ikke starte optagelsen.',
      );
    } on MissingPluginException {
      _running = false;
      throw const TranscriberException(
        TranscriberUnavailable.platformUnsupported,
        'Der er ingen talegenkendelse i denne build.',
      );
    }
  }

  static TranscriberUnavailable _reason(String code) => switch (code) {
        'permissionDenied' => TranscriberUnavailable.permissionDenied,
        'localeUnsupported' => TranscriberUnavailable.localeUnsupported,
        'noInput' => TranscriberUnavailable.noInput,
        _ => TranscriberUnavailable.failed,
      };

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['type']) {
      case 'segment':
        final text = '${event['text'] ?? ''}';
        if (text.trim().isEmpty) return;
        _segments.add(TranscriptSegment(
          text: text,
          isFinal: event['isFinal'] == true,
          at: DateTime.fromMillisecondsSinceEpoch(
            (event['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          ),
          confidence: (event['confidence'] as num?)?.toDouble(),
        ));

      case 'error':
        _running = false;
        _segments.addError(TranscriberException(
          _reason('${event['code']}'),
          '${event['message'] ?? 'Noget gik galt under optagelsen.'}',
        ));

      case 'stopped':
        // The recogniser can end on its own — silence, a time limit, an error.
        // Reflecting that here is what stops the UI showing a live indicator
        // for a session that is already over.
        _running = false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    try {
      await _methods.invokeMethod<void>('speechStop');
    } on PlatformException catch (e) {
      debugPrint('Kunne ikke stoppe optagelsen rent: ${e.message}');
    } on MissingPluginException {
      // Nothing to stop without a platform side.
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _native?.cancel();
    _native = null;
    await _segments.close();
  }
}
