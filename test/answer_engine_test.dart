import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/data/db/local_database.dart';
import 'package:glemtdet/data/repositories/sqlite_memory_repository.dart';
import 'package:glemtdet/domain/models/observation.dart';
import 'package:glemtdet/domain/services/answer_engine.dart';
import 'package:glemtdet/vision/interpretation/local_answer_engine.dart';

void main() {
  late Directory scratch;
  late LocalDatabase db;
  late SqliteMemoryRepository repository;
  late LocalAnswerEngine engine;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('glemtdet_answers');
    db = LocalDatabase.openInMemory(scratch);
    repository = SqliteMemoryRepository(db);
    engine = LocalAnswerEngine(repository);
  });

  tearDown(() {
    db.close();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  Future<void> seed({
    String object = 'headphones',
    String label = 'Høretelefoner',
    String? place = 'desk',
    String? placeLabel = 'Skrivebord',
    double placeConfidence = 0.8,
    DateTime? at,
    double confidence = 0.94,
  }) async {
    await repository.recordObservation(ObservationDraft(
      objectKey: object,
      objectLabel: label,
      confidence: confidence,
      seenAt: at ?? DateTime.now().subtract(const Duration(minutes: 5)),
      placeKey: place,
      placeLabel: placeLabel,
      placeConfidence: place == null ? null : placeConfidence,
      backend: 'test',
    ));
  }

  group('forståelse af spørgsmålet', () {
    test('genkender objektet i almindeligt dansk', () {
      // The model has one label for all of these, so they all resolve to it.
      for (final q in [
        'Hvor er mine AirPods?',
        'hvor lagde jeg mine airpods',
        'har du set mine ørepropper',
        'Hvor er mit headset?',
        'hvor er mine hovedtelefoner',
      ]) {
        expect(engine.parse(q).objectKey, 'headphones', reason: q);
      }

      expect(engine.parse('Hvor er min taske?').objectKey, 'bag');
      expect(engine.parse('Hvor er mine briller?').objectKey, 'glasses');
      expect(engine.parse('Hvor er min mobil?').objectKey, 'phone');
      expect(engine.parse('Hvor er min pung?').objectKey, 'wallet');
      expect(engine.parse('Hvor er mine sko?').objectKey, 'shoes');
    });

    test('tåler stavefejl og manglende danske tegn', () {
      expect(engine.parse('hvor er min telefpn').objectKey, 'phone');
      expect(engine.parse('hvor er mine hoeretelefoner').objectKey, 'headphones');
      expect(engine.parse('hvor er mine brller').objectKey, 'glasses');
    });

    test('skelner hvor fra hvornår', () {
      expect(engine.parse('Hvor er min telefon?').intent, QueryIntent.whereIsObject);
      expect(engine.parse('Hvornår så jeg min telefon?').intent, QueryIntent.whenWasObject);
      expect(engine.parse('Hvad ligger på skrivebordet?').intent, QueryIntent.whatIsAtPlace);
    });

    test('finder stedet i et sted-spørgsmål', () {
      expect(engine.parse('Hvad ligger på skrivebordet?').placeKey, 'desk');
      expect(engine.parse('Hvad er der i sofaen?').placeKey, 'sofa');
    });
  });

  group('blinde vinkler', () {
    test('siger ligeud at nøgler aldrig kan findes', () async {
      await seed();
      final answer = await engine.answer('Hvor er mine nøgler?');
      expect(answer.text, contains('kan ikke genkende nøgler'));
      expect(answer.text, contains('aldrig'));
      expect(answer.isConfident, isFalse);
      // Crucially, it does not say "jeg har ikke set dem endnu".
      expect(answer.text, isNot(contains('endnu')));
    });

    test('forklarer at en oplader ikke kan skelnes fra en ledning', () async {
      final answer = await engine.answer('Hvor lagde jeg min oplader?');
      expect(answer.text, contains('Ledning'));
      expect(answer.isConfident, isFalse);
    });

    test('en tablet er også en blind vinkel', () async {
      final answer = await engine.answer('Har du set min iPad?');
      expect(answer.text, contains('kan ikke genkende en tablet'));
    });
  });

  group('svarene', () {
    test('svarer med sted og tidspunkt når det er sikkert', () async {
      await seed(at: DateTime.now().subtract(const Duration(minutes: 3)));

      final answer = await engine.answer('Hvor er mine høretelefoner?');
      expect(answer.text, contains('dine høretelefoner'));
      expect(answer.text, contains('på skrivebordet'));
      expect(answer.text, contains('kl.'));
      expect(answer.isConfident, isTrue);
      expect(answer.primary, isNotNull);
    });

    test('advarer om at AirPods ikke kan skelnes fra andre høretelefoner', () async {
      await seed();
      final answer = await engine.answer('Hvor er mine AirPods?');
      expect(answer.caveat, isNotNull);
      expect(answer.caveat, contains('skelner ikke'));
      // The sentence itself stays short; the caveat sits beside it.
      expect(answer.text, contains('på skrivebordet'));
    });

    test('nævner naboobjektet fra samme billede', () async {
      final at = DateTime.now().subtract(const Duration(minutes: 2));
      await repository.recordObservation(ObservationDraft(
        objectKey: 'headphones',
        objectLabel: 'Høretelefoner',
        confidence: 0.9,
        seenAt: at,
        placeKey: 'desk',
        placeLabel: 'Skrivebord',
        placeConfidence: 0.8,
      ));
      await repository.recordObservation(ObservationDraft(
        objectKey: 'computer',
        objectLabel: 'Computer',
        confidence: 0.9,
        seenAt: at.add(const Duration(seconds: 1)),
        placeKey: 'desk',
        placeLabel: 'Skrivebord',
        placeConfidence: 0.8,
      ));

      final answer = await engine.answer('Hvor er mine høretelefoner?');
      expect(answer.text, contains('ved siden af din computer'));
    });

    test('er ærlig når placeringen er upræcis', () async {
      await seed(place: 'table', placeLabel: 'Bord', placeConfidence: 0.30);
      final answer = await engine.answer('Hvor er mine høretelefoner?');
      expect(answer.text, contains('på et bord'));
      expect(answer.text, contains('kunne ikke afgøre præcis'));
      expect(answer.isConfident, isFalse);
    });

    test('er ærlig når der slet ingen placering er', () async {
      await seed(place: null, placeLabel: null);
      final answer = await engine.answer('Hvor er mine høretelefoner?');
      expect(answer.text, contains('kunne ikke se hvor'));
      expect(answer.isConfident, isFalse);
    });

    test('siger det ligeud når objektet aldrig er set', () async {
      await seed(object: 'bag', label: 'Taske');
      final answer = await engine.answer('Hvor er mine briller?');
      expect(answer.text, contains('har ikke set dine briller'));
      expect(answer.isConfident, isFalse);
      expect(answer.primary, isNull);
    });

    test('advarer når observationen er gammel', () async {
      await seed(at: DateTime.now().subtract(const Duration(days: 3)));
      final answer = await engine.answer('Hvor er mine høretelefoner?');
      expect(answer.text, contains('3 dage siden'));
      expect(answer.isConfident, isFalse);
    });

    test('svarer på hvornår med et tidspunkt', () async {
      await seed(at: DateTime.now().subtract(const Duration(hours: 2)));
      final answer = await engine.answer('Hvornår så jeg mine høretelefoner?');
      expect(answer.text, startsWith('Jeg så dine høretelefoner'));
      expect(answer.text, contains('kl.'));
    });

    test('opsummerer hvad der ligger et sted', () async {
      await seed();
      await seed(object: 'glasses', label: 'Briller');
      final answer = await engine.answer('Hvad ligger på skrivebordet?');
      expect(answer.text, contains('på skrivebordet'));
      expect(answer.text, contains('høretelefoner'));
      expect(answer.text, contains('briller'));
    });

    test('nævner vanen når tingen ligger et usædvanligt sted', () async {
      for (var i = 0; i < 4; i++) {
        await seed(at: DateTime.now().subtract(Duration(days: 5 + i)));
      }
      await seed(
        place: 'sofa',
        placeLabel: 'Sofa',
        at: DateTime.now().subtract(const Duration(minutes: 4)),
      );

      final answer = await engine.answer('Hvor er mine høretelefoner?');
      expect(answer.text, contains('i sofaen'));
      expect(answer.text, contains('Normalt ligger de på skrivebordet'));
    });

    test('beder om et objekt når spørgsmålet er uforståeligt', () async {
      await seed();
      final answer = await engine.answer('øh hvad så');
      expect(answer.isConfident, isFalse);
      expect(answer.text, contains('Høretelefoner'));
    });

    test('siger at hukommelsen er tom når den er tom', () async {
      final answer = await engine.answer('Hvor er min tandbørste?');
      expect(answer.text, contains('ikke set noget endnu'));
    });
  });
}
