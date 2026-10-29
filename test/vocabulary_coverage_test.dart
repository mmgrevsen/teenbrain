// Holds the Danish taxonomy up against the vocabulary Apple Vision really has.
//
// `test/fixtures/apple_vision_vocabulary.txt` is a verbatim dump of
// `VNClassifyImageRequest.knownClassifications` from this Mac, produced by
// `integration_test/vision_backend_test.dart`. Checking against it here means
// the mapping cannot quietly rot: if a kind loses every label it can match, or
// a documented blind spot turns out to be covered after all, this fails.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/vision/taxonomy/blind_spots.dart';
import 'package:glemtdet/vision/taxonomy/object_taxonomy.dart';
import 'package:glemtdet/vision/taxonomy/place_taxonomy.dart';

void main() {
  late List<String> vocabulary;

  setUpAll(() {
    final file = File('test/fixtures/apple_vision_vocabulary.txt');
    vocabulary = file.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
  });

  test('fixturen ligner det Vision faktisk kender', () {
    expect(vocabulary.length, greaterThan(1200));
    expect(vocabulary, contains('eyeglasses'));
    expect(vocabulary, contains('headphones'));
    expect(vocabulary, contains('desk'));
  });

  test('hver objekttype kan faktisk genkendes', () {
    final taxonomy = ObjectTaxonomy.standard;
    final orphans = <String>[];
    for (final kind in taxonomy.kinds) {
      if (taxonomy.coverageFor(kind.key, vocabulary).isEmpty) orphans.add(kind.label);
    }
    expect(orphans, isEmpty,
        reason: 'Disse objekttyper kan modellen aldrig se — flyt dem til '
            'blind_spots.dart eller find de rigtige labels: ${orphans.join(', ')}');
  });

  test('hvert sted kan faktisk genkendes', () {
    final taxonomy = PlaceTaxonomy.standard;
    final orphans = <String>[];
    for (final kind in taxonomy.kinds) {
      final hits = vocabulary.where((l) => taxonomy.match(l, 1.0)?.kind.key == kind.key);
      if (hits.isEmpty) orphans.add(kind.label);
    }
    expect(orphans, isEmpty,
        reason: 'Disse steder kan modellen aldrig genkende: ${orphans.join(', ')}');
  });

  test('de blinde vinkler er stadig blinde', () {
    // If a future model learns keys, this fails and tells you to delete the
    // entry rather than keep apologising for something that now works.
    final taxonomy = ObjectTaxonomy.standard;
    for (final spot in kAppleVisionBlindSpots) {
      final claimed = vocabulary.where((l) => taxonomy.match(l, 1.0)?.kind.key == spot.key);
      expect(claimed, isEmpty,
          reason: '"${spot.label}" er ikke længere en blind vinkel — '
              'fjern den fra blind_spots.dart.');
    }
    // Keys specifically: no label in the whole vocabulary is one.
    final keyish = vocabulary.where((l) => l == 'key' || l == 'keys' || l == 'keychain');
    expect(keyish, isEmpty);
  });

  test('ingen label bliver til to forskellige objekter', () {
    // Ambiguity here means two kinds fight over the same evidence and the
    // winner depends on list order.
    final taxonomy = ObjectTaxonomy.standard;
    final byLabel = <String, List<String>>{};
    for (final label in vocabulary) {
      final match = taxonomy.match(label, 1.0);
      if (match != null) byLabel.putIfAbsent(label, () => []).add(match.kind.key);
    }
    for (final entry in byLabel.entries) {
      expect(entry.value.toSet(), hasLength(1), reason: 'flertydig label: ${entry.key}');
    }
  });

  test('mapningen er selektiv — den sluger ikke halvdelen af ordforrådet', () {
    final taxonomy = ObjectTaxonomy.standard;
    final matched = vocabulary.where((l) => taxonomy.match(l, 1.0) != null).length;
    // Around a hundred of 1303 labels are household objects worth remembering.
    // Far more than that means the excludes have stopped working.
    expect(matched, lessThan(160),
        reason: '$matched labels matcher — for løs mapning.');
    expect(matched, greaterThan(50));
  });

  test('objekter og steder overlapper kun hvor det giver mening', () {
    // A bag is both a thing you lose and a place you put things in; a laptop
    // is not a place.
    final objects = ObjectTaxonomy.standard;
    final places = PlaceTaxonomy.standard;
    final overlap = <String>[];
    for (final label in vocabulary) {
      final o = objects.match(label, 1.0);
      final p = places.match(label, 1.0);
      if (o != null && p != null && o.kind.key != p.kind.key) overlap.add(label);
    }
    expect(overlap, everyElement(anyOf(contains('bag'), contains('backpack'),
        contains('briefcase'), contains('luggage'), contains('suitcase'))),
        reason: 'uventet overlap: ${overlap.join(', ')}');
  });
}
