import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/vision/taxonomy/blind_spots.dart';
import 'package:glemtdet/vision/taxonomy/object_taxonomy.dart';
import 'package:glemtdet/vision/taxonomy/place_taxonomy.dart';

void main() {
  final objects = ObjectTaxonomy.standard;
  final places = PlaceTaxonomy.standard;

  group('normalisering', () {
    test('gør backend-navne sammenlignelige', () {
      expect(normalizeLabel('computer_keyboard'), 'computer keyboard');
      expect(normalizeLabel('Computer-Keyboard'), 'computer keyboard');
      expect(normalizeLabel('  CELL   PHONE '), 'cell phone');
    });
  });

  group('objektgenkendelse', () {
    test('rammer de labels Apple Vision faktisk udsender', () {
      final cases = {
        'phone': 'phone',
        'headphones': 'headphones',
        'laptop': 'computer',
        'computer_keyboard': 'computer',
        'backpack': 'bag',
        'wallet': 'wallet',
        'bottle': 'bottle',
        'book': 'book',
        'gamepad': 'controller',
        'eyeglasses': 'glasses',
        'jacket': 'clothing',
        'sneaker': 'shoes',
        'computer_mouse': 'mouse',
        'cord': 'cable',
        'passport': 'passport',
      };
      for (final entry in cases.entries) {
        final match = objects.match(entry.key, 0.8);
        expect(match, isNotNull, reason: '${entry.key} burde matche');
        expect(match!.kind.key, entry.value, reason: 'forkert kind for ${entry.key}');
      }
    });

    test('afviser de fælder ordforrådet faktisk indeholder', () {
      // Every one of these is a real Apple Vision label that a naive matcher
      // would swallow.
      expect(objects.match('thermostat', 0.9), isNull, reason: 'et termostat er ikke en termokande');
      expect(objects.match('iron_clothing', 0.9), isNull, reason: 'et strygejern er ikke tøj');
      expect(objects.match('megaphone', 0.9), isNull);
      expect(objects.match('payphone', 0.9), isNull);
      expect(objects.match('saxophone', 0.9), isNull);
      expect(objects.match('microphone', 0.9), isNull);
      expect(objects.match('bookshelf', 0.9), isNull, reason: 'en reol er et sted, ikke en bog');
      expect(objects.match('bagel', 0.9), isNull);
      expect(objects.match('horseshoe', 0.9), isNull);
      expect(objects.match('mousetrap', 0.9), isNull);
      expect(objects.match('wine_bottle', 0.9), isNull);
      expect(objects.match('drinking_glass', 0.9), isNull);
      expect(objects.match('keypad', 0.9), isNull);
      expect(objects.match('clock', 0.9), isNull, reason: 'et vægur bliver ikke væk');
    });

    test('computer_mouse bliver en mus, ikke en computer', () {
      expect(objects.match('computer_mouse', 0.9)?.kind.key, 'mouse');
      expect(objects.match('computer', 0.9)?.kind.key, 'computer');
    });

    test('respekterer minimumstærskel', () {
      expect(objects.match('laptop', 0.01), isNull);
      expect(objects.match('laptop', 0.5), isNotNull);
    });

    test('dækningsanalysen finder umatchede labels', () {
      final vocabulary = ['laptop', 'volcano', 'eyeglasses', 'waterfall'];
      expect(objects.unmapped(vocabulary), containsAll(['volcano', 'waterfall']));
      expect(objects.coverageFor('glasses', vocabulary), contains('eyeglasses'));
    });
  });

  group('blinde vinkler', () {
    test('nøgler, oplader og tablet er ikke objekttyper', () {
      // They must not sit in the taxonomy pretending to be detectable.
      final keys = objects.kinds.map((k) => k.key).toSet();
      expect(keys, isNot(contains('keys')));
      expect(keys, isNot(contains('charger')));
      expect(keys, isNot(contains('tablet')));
    });

    test('men de bliver genkendt i et spørgsmål', () {
      expect(blindSpotFor('hvor er mine noegler', kAppleVisionBlindSpots)?.key, 'keys');
      expect(blindSpotFor('hvor er min oplader', kAppleVisionBlindSpots)?.key, 'charger');
      expect(blindSpotFor('hvor er min ipad', kAppleVisionBlindSpots)?.key, 'tablet');
      expect(blindSpotFor('hvor er min telefon', kAppleVisionBlindSpots), isNull);
    });

    test('forklaringen siger hvorfor, ikke bare at det ikke lykkedes', () {
      final keys = kAppleVisionBlindSpots.firstWhere((s) => s.key == 'keys');
      expect(keys.explanation, contains('kan ikke'));
      expect(keys.explanation, contains('aldrig'));
    });
  });

  group('stedgenkendelse', () {
    test('kender de steder ordforrådet dækker', () {
      final cases = {
        'desk': 'desk',
        'bed': 'bed',
        'kitchen': 'kitchen_counter',
        'kitchen_sink': 'kitchen_counter',
        'sofa': 'sofa',
        'living_room': 'sofa',
        'bookshelf': 'shelf',
        'backpack': 'bag',
        'dining_room': 'dining_table',
        'bathroom': 'bathroom',
        'car': 'car',
      };
      for (final entry in cases.entries) {
        expect(places.match(entry.key, 0.7)?.kind.key, entry.value,
            reason: 'forkert sted for ${entry.key}');
      }
    });

    test('undgår de falske positive ordforrådet indeholder', () {
      expect(places.match('vegetable', 0.9), isNull);
      expect(places.match('cardboard_box', 0.9), isNull);
      expect(places.match('carrot', 0.9), isNull);
      expect(places.match('carousel', 0.9), isNull);
      expect(places.match('chairlift', 0.9), isNull, reason: 'en stolelift er ikke en stol');
      expect(places.match('tableware', 0.9), isNull, reason: 'service er ikke et bord');
      expect(places.match('bagel', 0.9), isNull);
    });

    test('vægter specifikke steder højere end vage', () {
      final desk = places.match('desk', 0.5)!;
      final table = places.match('table', 0.5)!;
      expect(desk.confidence, greaterThan(table.confidence));
      expect(desk.kind.specificity, PlaceSpecificity.surface);
      expect(table.kind.specificity, PlaceSpecificity.vague);
    });

    test('steder uden ord i modellen er udeladt', () {
      // Vision has no floor, carpet, nightstand or windowsill. Listing them
      // would promise an answer that can never be given.
      final keys = places.kinds.map((k) => k.key).toSet();
      expect(keys, isNot(contains('floor')));
      expect(keys, isNot(contains('nightstand')));
      expect(keys, isNot(contains('window')));
    });
  });
}
