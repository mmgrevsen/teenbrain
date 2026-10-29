/// The seam between TeenBrain and whatever turns speech into text.
///
/// Nothing in this file names Apple, and nothing outside `lib/transcription/`
/// may. On-device `SFSpeechRecognizer` is the first implementation because it
/// is free, works offline and handles Danish well — but a cloud recogniser is
/// one class and one branch away, and the rest of the app would not notice.
library;

import 'package:meta/meta.dart';

/// Why transcription is unavailable, so the UI can say something true instead
/// of showing a record button that does nothing.
enum TranscriberUnavailable {
  /// This build has no implementation for the platform.
  platformUnsupported,

  /// The user has not granted microphone or speech access.
  permissionDenied,

  /// The OS has no recogniser for the requested language.
  localeUnsupported,

  /// The microphone itself is missing or in use elsewhere.
  noInput,

  /// Something else went wrong; [TranscriberException.message] says what.
  failed,
}

class TranscriberException implements Exception {
  const TranscriberException(this.reason, this.message);

  final TranscriberUnavailable reason;
  final String message;

  @override
  String toString() => 'TranscriberException($reason): $message';
}

/// Two separate grants on macOS: the microphone, and speech recognition.
/// Both have to be allowed, and the UI has to be able to tell which is missing.
enum TranscriberPermission { granted, denied, notDetermined, restricted }

@immutable
class TranscriberAccess {
  const TranscriberAccess({required this.microphone, required this.speech});

  final TranscriberPermission microphone;
  final TranscriberPermission speech;

  bool get isGranted =>
      microphone == TranscriberPermission.granted &&
      speech == TranscriberPermission.granted;

  /// True while at least one grant has never been asked for — the state where
  /// showing the OS prompt is the right next step.
  bool get canAsk =>
      microphone == TranscriberPermission.notDetermined ||
      speech == TranscriberPermission.notDetermined;

  /// What to tell the user, in Danish, when [isGranted] is false.
  String? get blockedReason {
    if (isGranted) return null;
    if (canAsk) return null;
    final missing = <String>[
      if (microphone != TranscriberPermission.granted) 'mikrofonen',
      if (speech != TranscriberPermission.granted) 'talegenkendelse',
    ];
    return 'TeenBrain mangler adgang til ${missing.join(' og ')}. '
        'Giv adgang under Systemindstillinger → Anonymitet og sikkerhed.';
  }
}

/// A piece of recognised speech.
///
/// Recognisers revise themselves as they hear more, so a segment arrives many
/// times as [isFinal] false and once as true. The UI shows the running text;
/// only final segments are kept.
@immutable
class TranscriptSegment {
  const TranscriptSegment({
    required this.text,
    required this.isFinal,
    required this.at,
    this.confidence,
  });

  final String text;
  final bool isFinal;
  final DateTime at;

  /// 0..1 where the recogniser reports one. Null when it does not.
  final double? confidence;

  bool get isEmpty => text.trim().isEmpty;
}

/// A live speech-to-text session.
abstract class Transcriber {
  /// Whether this build can transcribe at all on this platform. False makes
  /// the Live Notes page explain itself rather than offer a dead button.
  bool get isSupported;

  /// Why not, when [isSupported] is false.
  String get unsupportedExplanation;

  /// Identifier for the UI: 'apple_speech'.
  String get backendId;

  /// What to show the user: "Apples talegenkendelse, lokalt".
  String get backendLabel;

  /// True when the recogniser runs entirely on the device. The Privacy page
  /// says so out loud, because "the microphone is on" means something very
  /// different depending on this answer.
  bool get isOnDevice;

  Future<TranscriberAccess> checkPermission();

  /// Triggers the OS prompts. Returns the state afterwards.
  Future<TranscriberAccess> requestPermission();

  bool get isRunning;

  /// Starts listening. Throws [TranscriberException] when it cannot.
  Future<void> start({String localeId = 'da-DK'});

  Future<void> stop();

  /// Segments as they are recognised. Closes when the session stops.
  Stream<TranscriptSegment> get segments;

  Future<void> dispose();
}
