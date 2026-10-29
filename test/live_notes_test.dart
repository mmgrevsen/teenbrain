/// The Live Notes session, driven by a fake recogniser.
///
/// The Swift side cannot be compiled on this machine, so these tests pin down
/// everything on the Dart side of the channel: the two permission grants, the
/// difference between a revision and a finished sentence, a recogniser that
/// stops on its own, and the rule that nothing records with the microphone
/// switched off.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/brain/live_notes_service.dart';
import 'package:glemtdet/domain/services/transcriber.dart';
import 'package:glemtdet/transcription/fallback/unavailable_transcriber.dart';

class FakeTranscriber implements Transcriber {
  FakeTranscriber({
    this.supported = true,
    this.microphone = TranscriberPermission.granted,
    this.speech = TranscriberPermission.granted,
    this.failOnStart,
  });

  bool supported;
  TranscriberPermission microphone;
  TranscriberPermission speech;
  TranscriberException? failOnStart;

  /// What the OS prompt would turn `notDetermined` into.
  TranscriberPermission? grantsOnRequest;

  final _controller = StreamController<TranscriptSegment>.broadcast();
  bool _running = false;
  int requestCount = 0;
  int stopCount = 0;

  @override
  bool get isSupported => supported;
  @override
  String get unsupportedExplanation => 'Ikke på denne platform.';
  @override
  String get backendId => 'fake';
  @override
  String get backendLabel => 'Fake';
  @override
  bool get isOnDevice => true;
  @override
  bool get isRunning => _running;
  @override
  Stream<TranscriptSegment> get segments => _controller.stream;

  @override
  Future<TranscriberAccess> checkPermission() async =>
      TranscriberAccess(microphone: microphone, speech: speech);

  @override
  Future<TranscriberAccess> requestPermission() async {
    requestCount++;
    final granted = grantsOnRequest ?? TranscriberPermission.granted;
    if (microphone == TranscriberPermission.notDetermined) microphone = granted;
    if (speech == TranscriberPermission.notDetermined) speech = granted;
    return TranscriberAccess(microphone: microphone, speech: speech);
  }

  @override
  Future<void> start({String localeId = 'da-DK'}) async {
    if (failOnStart != null) throw failOnStart!;
    _running = true;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _running = false;
  }

  @override
  Future<void> dispose() async {
    _running = false;
    await _controller.close();
  }

  // -- test helpers ---------------------------------------------------------

  void hear(String text, {bool isFinal = false}) {
    _controller.add(TranscriptSegment(
      text: text,
      isFinal: isFinal,
      at: DateTime.now(),
    ));
  }

  /// The recogniser giving up by itself — silence, a time limit, an error.
  void fail(String message) {
    _running = false;
    _controller.addError(
      TranscriberException(TranscriberUnavailable.failed, message),
    );
  }
}

void main() {
  late FakeTranscriber fake;
  late LiveNotesService service;
  var micOn = true;

  setUp(() {
    micOn = true;
    fake = FakeTranscriber();
    service = LiveNotesService(
      transcriber: fake,
      microphoneEnabled: () => micOn,
    );
  });

  tearDown(() async {
    await service.dispose();
  });

  /// Segments arrive asynchronously; let the stream deliver.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('tilladelser', () {
    test('spørger kun når der er noget at spørge om', () async {
      expect(await service.start(), isTrue);
      expect(fake.requestCount, 0);
    });

    test('spørger når en tilladelse aldrig er besvaret', () async {
      fake.microphone = TranscriberPermission.notDetermined;
      expect(await service.start(), isTrue);
      expect(fake.requestCount, 1);
      expect(service.state.isListening, isTrue);
    });

    test('et afslag starter ikke, og siger hvad der mangler', () async {
      fake.microphone = TranscriberPermission.denied;
      expect(await service.start(), isFalse);
      expect(service.state.status, LiveNotesStatus.error);
      expect(service.state.error, contains('mikrofonen'));
      expect(service.state.error, isNot(contains('talegenkendelse')));
    });

    test('mangler begge, nævnes begge', () async {
      fake.microphone = TranscriberPermission.denied;
      fake.speech = TranscriberPermission.denied;
      await service.start();
      expect(service.state.error, contains('mikrofonen og talegenkendelse'));
    });

    test('et afslag på selve prompten starter heller ikke', () async {
      fake.microphone = TranscriberPermission.notDetermined;
      fake.speech = TranscriberPermission.notDetermined;
      fake.grantsOnRequest = TranscriberPermission.denied;

      expect(await service.start(), isFalse);
      expect(fake.requestCount, 1);
      expect(service.state.status, LiveNotesStatus.error);
    });
  });

  group('privacy-kontakten', () {
    test('slået fra optager ingenting, og spørger ikke engang', () async {
      micOn = false;
      expect(await service.start(), isFalse);
      expect(fake.isRunning, isFalse);
      expect(fake.requestCount, 0);
      expect(service.state.error, contains('Privatliv'));
    });

    test('kontakten læses ved hvert forsøg, ikke én gang', () async {
      micOn = false;
      expect(await service.start(), isFalse);

      micOn = true;
      expect(await service.start(), isTrue);
      expect(service.state.isListening, isTrue);
    });
  });

  group('transskription', () {
    test('en revideret sætning erstatter sig selv indtil den er endelig', () async {
      await service.start();

      fake.hear('Den franske');
      await settle();
      expect(service.state.transcript, 'Den franske');

      fake.hear('Den franske revolution');
      await settle();
      // Ikke "Den franske Den franske revolution".
      expect(service.state.transcript, 'Den franske revolution');
      expect(service.state.committed, isEmpty);
      expect(service.state.pending, 'Den franske revolution');
    });

    test('en endelig sætning lægges fast, og den næste starter forfra', () async {
      await service.start();

      fake.hear('Revolutionen begyndte i 1789.', isFinal: true);
      await settle();
      expect(service.state.committed, 'Revolutionen begyndte i 1789.');
      expect(service.state.pending, isEmpty);

      fake.hear('Louis');
      await settle();
      expect(service.state.transcript, 'Revolutionen begyndte i 1789. Louis');
      expect(service.state.committed, 'Revolutionen begyndte i 1789.');
    });

    test('tomme segmenter ignoreres', () async {
      await service.start();
      fake.hear('   ');
      await settle();
      expect(service.state.hasText, isFalse);
    });

    test('ordtælling dækker også den sætning der er i gang', () async {
      await service.start();
      fake.hear('Et to tre', isFinal: true);
      fake.hear('fire fem');
      await settle();
      expect(service.state.wordCount, 5);
    });

    test('stop beholder den sidste sætning, selvom den ikke nåede at blive endelig',
        () async {
      await service.start();
      fake.hear('Afsluttende pointe', isFinal: true);
      fake.hear('som læreren nåede lige akkurat');
      await settle();

      final transcript = await service.stop();
      expect(transcript, 'Afsluttende pointe som læreren nåede lige akkurat');
      expect(service.state.status, LiveNotesStatus.idle);
      expect(fake.stopCount, 1);
    });
  });

  group('når det går galt', () {
    test('en fejl ved start bliver til en besked, ikke en exception', () async {
      fake.failOnStart = const TranscriberException(
        TranscriberUnavailable.localeUnsupported,
        'Dansk kan ikke genkendes lokalt på denne Mac.',
      );
      expect(await service.start(), isFalse);
      expect(service.state.status, LiveNotesStatus.error);
      expect(service.state.error, contains('lokalt'));
    });

    test('en genkender der selv giver op, slukker indikatoren', () async {
      await service.start();
      expect(service.state.isListening, isTrue);

      fake.fail('Talegenkendelsen blev utilgængelig.');
      await settle();

      expect(service.state.status, LiveNotesStatus.error);
      expect(service.state.isListening, isFalse);
      expect(service.state.error, contains('utilgængelig'));
    });

    test('tekst der allerede var hørt, går ikke tabt ved en fejl', () async {
      await service.start();
      fake.hear('Vigtig pointe', isFinal: true);
      await settle();

      fake.fail('Mistede forbindelsen til mikrofonen.');
      await settle();

      expect(service.state.committed, 'Vigtig pointe');
    });

    test('to kald til start giver ikke to sessioner', () async {
      expect(await service.start(), isTrue);
      expect(await service.start(), isFalse);
    });

    test('stop uden en session er harmløs', () async {
      expect(await service.stop(), isEmpty);
      expect(fake.stopCount, 0);
    });

    test('reset rydder alt', () async {
      await service.start();
      fake.hear('Noget', isFinal: true);
      await settle();
      await service.stop();

      service.reset();
      expect(service.state.hasText, isFalse);
      expect(service.state.status, LiveNotesStatus.idle);
      expect(service.state.startedAt, isNull);
    });
  });

  group('platforme uden talegenkendelse', () {
    test('siger det i stedet for at tilbyde en død knap', () async {
      final unsupported = LiveNotesService(
        transcriber: const UnavailableTranscriber('Ikke på Windows endnu.'),
        microphoneEnabled: () => true,
      );
      addTearDown(unsupported.dispose);

      expect(unsupported.isSupported, isFalse);
      expect(await unsupported.start(), isFalse);
      expect(unsupported.state.error, 'Ikke på Windows endnu.');
    });

    test('den uforklarede fallback kaster med en grund, ikke bare en fejl', () async {
      const transcriber = UnavailableTranscriber('Ikke her.');
      expect(
        () => transcriber.start(),
        throwsA(isA<TranscriberException>().having(
          (e) => e.reason,
          'reason',
          TranscriberUnavailable.platformUnsupported,
        )),
      );
    });
  });

  group('tilstanden som UI\'et læser', () {
    test('forløbet tid måles fra sessionens start', () async {
      await service.start();
      final started = service.state.startedAt;
      expect(started, isNotNull);
      expect(
        service.state.elapsed(started!.add(const Duration(seconds: 42)))!.inSeconds,
        42,
      );
    });

    test('tilstandsstrømmen fortæller om hvert skridt', () async {
      final seen = <LiveNotesStatus>[];
      final sub = service.states.listen((s) => seen.add(s.status));
      addTearDown(sub.cancel);

      await service.start();
      await service.stop();
      await settle();

      expect(seen, containsAllInOrder([
        LiveNotesStatus.starting,
        LiveNotesStatus.listening,
        LiveNotesStatus.stopping,
        LiveNotesStatus.idle,
      ]));
    });
  });
}
