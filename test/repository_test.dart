import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/data/db/local_database.dart';
import 'package:glemtdet/data/repositories/sqlite_memory_repository.dart';
import 'package:glemtdet/domain/models/detection.dart';
import 'package:glemtdet/domain/models/observation.dart';
import 'package:glemtdet/domain/repositories/memory_repository.dart';

/// Two bytes is enough to prove the file is written and deleted; the codec is
/// not what is under test here.
final _fakeJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

ObservationDraft draft({
  String object = 'airpods',
  String label = 'AirPods',
  String? place = 'desk',
  String? placeLabel = 'Skrivebord',
  double confidence = 0.9,
  DateTime? at,
}) =>
    ObservationDraft(
      objectKey: object,
      objectLabel: label,
      confidence: confidence,
      seenAt: at ?? DateTime(2026, 9, 4, 18, 42),
      placeKey: place,
      placeLabel: placeLabel,
      placeConfidence: place == null ? null : 0.7,
      bounds: const NormRect(0.1, 0.2, 0.3, 0.25),
      rawLabels: const [RawLabel(identifier: 'earphone', confidence: 0.88)],
      backend: 'test',
    );

void main() {
  late Directory scratch;
  late LocalDatabase db;
  late SqliteMemoryRepository repository;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('glemtdet_test');
    db = LocalDatabase.openInMemory(scratch);
    repository = SqliteMemoryRepository(db);
  });

  tearDown(() {
    db.close();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('gemmer en observation med billede og læser den tilbage', () async {
    final saved = await repository.recordObservation(draft(), image: _fakeJpeg);

    expect(saved.id, greaterThan(0));
    expect(saved.imagePath, isNotNull);
    expect(File(saved.imagePath!).existsSync(), isTrue);

    final back = await repository.observationById(saved.id);
    expect(back!.objectLabel, 'AirPods');
    expect(back.placeLabel, 'Skrivebord');
    expect(back.bounds!.left, closeTo(0.1, 1e-9));
    expect(back.rawLabels.single.identifier, 'earphone');
    expect(back.placeCertainty, PlaceCertainty.confident);
  });

  test('opdaterer objekt- og stedaggregater', () async {
    await repository.recordObservation(draft(at: DateTime(2026, 9, 4, 10)));
    await repository.recordObservation(draft(at: DateTime(2026, 9, 4, 12)));

    final object = await repository.object('airpods');
    expect(object!.observationCount, 2);
    expect(object.firstSeen, DateTime(2026, 9, 4, 10));
    expect(object.lastSeen, DateTime(2026, 9, 4, 12));
    expect(object.lastPlaceLabel, 'Skrivebord');

    final places = await repository.places();
    expect(places.single.key, 'desk');
    expect(places.single.observationCount, 2);
  });

  test('lærer hvor et objekt normalt ligger', () async {
    for (var i = 0; i < 5; i++) {
      await repository.recordObservation(draft(at: DateTime(2026, 9, 1 + i, 9)));
    }
    await repository.recordObservation(
      draft(place: 'sofa', placeLabel: 'Sofa', at: DateTime(2026, 9, 7, 9)),
    );

    final habits = await repository.habitsFor('airpods');
    expect(habits.first.placeKey, 'desk');
    expect(habits.first.count, 5);
    expect(habits.first.totalForObject, 6);
    expect(habits.first.isStrong, isTrue);
    expect(habits.last.placeKey, 'sofa');
    expect(habits.last.isStrong, isFalse);
  });

  test('nyeste observation pr. objekt', () async {
    await repository.recordObservation(draft(at: DateTime(2026, 9, 4, 10)));
    await repository.recordObservation(draft(at: DateTime(2026, 9, 4, 18)));
    await repository.recordObservation(
      draft(object: 'keys', label: 'Nøgler', at: DateTime(2026, 9, 4, 17)),
    );

    final latest = await repository.latestPerObject();
    expect(latest.length, 2);
    expect(latest.first.objectKey, 'airpods');
    expect(latest.first.seenAt.hour, 18);
    expect(latest.last.objectKey, 'keys');
  });

  test('refresh flytter tidsstemplet uden at lave en ny række', () async {
    final saved = await repository.recordObservation(draft(confidence: 0.5));
    await repository.refreshObservation(
      saved.id,
      seenAt: DateTime(2026, 9, 4, 18, 45),
      confidence: 0.8,
    );

    final all = await repository.history(const HistoryFilter());
    expect(all.length, 1);
    expect(all.single.seenAt.minute, 45);
    expect(all.single.confidence, 0.8);

    // A refresh must never lower a confidence that was already better.
    await repository.refreshObservation(
      saved.id,
      seenAt: DateTime(2026, 9, 4, 18, 50),
      confidence: 0.2,
    );
    expect((await repository.observationById(saved.id))!.confidence, 0.8);
  });

  test('filtrerer historik på objekt og tid', () async {
    await repository.recordObservation(draft(at: DateTime(2026, 9, 1, 9)));
    await repository.recordObservation(
      draft(object: 'keys', label: 'Nøgler', at: DateTime(2026, 9, 4, 9)),
    );

    expect((await repository.history(const HistoryFilter(objectKey: 'keys'))).length, 1);
    expect(
      (await repository.history(HistoryFilter(after: DateTime(2026, 9, 3)))).length,
      1,
    );
    expect((await repository.history(const HistoryFilter(placeKey: 'desk'))).length, 2);
  });

  test('finder samtidige observationer', () async {
    final a = await repository.recordObservation(draft(at: DateTime(2026, 9, 4, 18, 42, 0)));
    await repository.recordObservation(
      draft(object: 'computer', label: 'Computer', at: DateTime(2026, 9, 4, 18, 42, 1)),
    );
    await repository.recordObservation(
      draft(object: 'bag', label: 'Taske', at: DateTime(2026, 9, 4, 20, 0, 0)),
    );

    final around = await repository.around(a.seenAt, excludeId: a.id);
    expect(around.map((o) => o.objectKey), ['computer']);
  });

  test('sletning fjerner billedet fra disken', () async {
    final saved = await repository.recordObservation(draft(), image: _fakeJpeg);
    final path = saved.imagePath!;
    expect(File(path).existsSync(), isTrue);

    await repository.deleteObservation(saved.id);
    expect(File(path).existsSync(), isFalse);
    expect(await repository.observationById(saved.id), isNull);
    // The object had only that one sighting, so it should be gone too.
    expect(await repository.object('airpods'), isNull);
  });

  test('slet alle billeder beholder den tekstlige hukommelse', () async {
    final saved = await repository.recordObservation(draft(), image: _fakeJpeg);
    await repository.eraseImages();

    expect(File(saved.imagePath!).existsSync(), isFalse);
    final back = await repository.observationById(saved.id);
    expect(back, isNotNull);
    expect(back!.imagePath, isNull);
    expect(back.objectLabel, 'AirPods');
  });

  test('slet alt tømmer hver tabel og hver fil', () async {
    await repository.recordObservation(draft(), image: _fakeJpeg);
    await repository.recordObservation(draft(object: 'keys', label: 'Nøgler'), image: _fakeJpeg);

    await repository.eraseAll();

    final stats = await repository.stats();
    expect(stats.observationCount, 0);
    expect(stats.objectCount, 0);
    expect(stats.placeCount, 0);
    expect(stats.imageCount, 0);
    expect(await repository.habitsFor('airpods'), isEmpty);
  });

  test('opbevaringspolitik fjerner gamle observationer og deres billeder', () async {
    final old = await repository.recordObservation(
      draft(at: DateTime(2026, 8, 1, 9)),
      image: _fakeJpeg,
    );
    await repository.recordObservation(draft(at: DateTime(2026, 9, 4, 9)));

    final removed = await repository.pruneBefore(DateTime(2026, 9, 1));
    expect(removed, 1);
    expect(File(old.imagePath!).existsSync(), isFalse);

    final object = await repository.object('airpods');
    expect(object!.observationCount, 1);
    final habits = await repository.habitsFor('airpods');
    expect(habits.single.count, 1);
  });

  test('eksport indeholder alt og kan udelade billedstier', () async {
    await repository.recordObservation(draft(), image: _fakeJpeg);

    final full = await repository.exportAll();
    expect(full['objects'], hasLength(1));
    expect(full['observations'], hasLength(1));
    expect((full['observations'] as List).first, contains('image_path'));

    final redacted = await repository.exportAll(includeImagePaths: false);
    expect((redacted['observations'] as List).first, isNot(contains('image_path')));
  });
}
