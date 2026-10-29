/// What every platform without a speech implementation gets.
///
/// It fails in one predictable way with one sentence the UI can show, which is
/// what lets the Live Notes page be written once.
library;

import 'dart:io';

import '../../domain/services/transcriber.dart';

class UnavailableTranscriber implements Transcriber {
  const UnavailableTranscriber(this.unsupportedExplanation);

  @override
  final String unsupportedExplanation;

  @override
  bool get isSupported => false;

  @override
  String get backendId => 'unavailable';

  @override
  String get backendLabel => 'Ingen talegenkendelse';

  @override
  bool get isOnDevice => false;

  @override
  bool get isRunning => false;

  @override
  Stream<TranscriptSegment> get segments => const Stream.empty();

  @override
  Future<TranscriberAccess> checkPermission() async => const TranscriberAccess(
        microphone: TranscriberPermission.restricted,
        speech: TranscriberPermission.restricted,
      );

  @override
  Future<TranscriberAccess> requestPermission() => checkPermission();

  @override
  Future<void> start({String localeId = 'da-DK'}) async {
    throw TranscriberException(
      TranscriberUnavailable.platformUnsupported,
      unsupportedExplanation,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Why this platform has no transcription, in words the Live Notes page shows.
String platformTranscriptionExplanation() {
  if (Platform.isWindows) {
    return 'Live Notes optager ikke på Windows endnu. Talegenkendelsen bygger på '
        'macOS\' egen motor, og Windows kræver en anden implementering, som ikke '
        'er skrevet. Du kan stadig indsætte tekst og få den struktureret.';
  }
  if (Platform.isIOS || Platform.isAndroid) {
    return 'Live Notes optager ikke på telefonen endnu.';
  }
  return 'Live Notes optager ikke på denne platform. Du kan stadig indsætte '
      'tekst og få den struktureret.';
}
