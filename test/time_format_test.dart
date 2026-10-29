import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/core/danish.dart';
import 'package:glemtdet/core/fuzzy.dart';
import 'package:glemtdet/core/time_format.dart';

void main() {
  final now = DateTime(2026, 9, 4, 20, 0);

  group('tid på dansk', () {
    test('klokkeslæt', () {
      expect(clockOf(DateTime(2026, 9, 4, 18, 42)), '18:42');
      expect(clockOf(DateTime(2026, 9, 4, 9, 5)), '09:05');
    });

    test('sætningsformen tilpasser sig hvor længe siden det er', () {
      expect(whenPhrase(DateTime(2026, 9, 4, 18, 42), now: now), 'kl. 18:42');
      expect(whenPhrase(DateTime(2026, 9, 3, 18, 42), now: now), 'i går kl. 18:42');
      expect(whenPhrase(DateTime(2026, 9, 2, 18, 42), now: now), 'i forgårs kl. 18:42');
      expect(whenPhrase(DateTime(2026, 8, 20, 18, 42), now: now), '20. august kl. 18:42');
    });

    test('dagsoverskrifter', () {
      expect(dayHeading(DateTime(2026, 9, 4, 1), now: now), 'I dag');
      expect(dayHeading(DateTime(2026, 9, 3, 1), now: now), 'I går');
    });

    test('hilsen følger tidspunktet', () {
      expect(greeting(now: DateTime(2026, 9, 4, 8)), 'Godmorgen');
      expect(greeting(now: DateTime(2026, 9, 4, 14)), 'God eftermiddag');
      expect(greeting(now: DateTime(2026, 9, 4, 20)), 'Godaften');
    });

    test('forbehold vokser med alderen', () {
      expect(stalenessCaveat(now.subtract(const Duration(minutes: 5)), now: now), isEmpty);
      expect(
        stalenessCaveat(now.subtract(const Duration(hours: 2)), now: now),
        contains('seneste observation'),
      );
      expect(
        stalenessCaveat(now.subtract(const Duration(days: 10)), now: now),
        contains('over en uge'),
      );
    });
  });

  group('dansk grammatik', () {
    test('vælger din/dit/dine korrekt', () {
      expect(yourObject('headphones', 'Høretelefoner'), 'dine høretelefoner');
      expect(yourObject('phone', 'Telefon'), 'din telefon');
      expect(yourObject('clothing', 'Tøj'), 'dit tøj');
      expect(yourObject('shoes', 'Sko'), 'dine sko');
      // A brand name keeps its capitals even in the middle of a sentence.
      expect(yourObject('unknown_key', 'AirPods'), 'din AirPods');
    });

    test('vælger på/i efter stedet', () {
      expect(placeGrammarFor('desk')!.located, 'på skrivebordet');
      expect(placeGrammarFor('outdoor')!.located, 'udendørs');
      expect(placeGrammarFor('sofa')!.located, 'i sofaen');
      expect(placeGrammarFor('table')!.locatedVague, 'på et bord');
    });

    test('folder danske tegn til noget søgbart', () {
      expect(foldDanish('Nøgler'), 'noegler');
      expect(foldDanish('Æblet på bordet!'), 'aeblet paa bordet');
      expect(foldDanish('Entré'), 'entre');
    });
  });

  group('fuzzy match', () {
    test('præfikser og stavefejl tæller, tilfældige bogstaver gør ikke', () {
      expect(termScore('airpods', 'airpods'), 1.0);
      expect(termScore('noegle', 'noegler'), greaterThan(0.5));
      expect(termScore('telefpn', 'telefon'), greaterThan(0.5));
      expect(termScore('x', 'telefon'), 0);
      expect(termScore('bord', 'telefon'), 0);
      // Danish definite forms are suffixes, so the query word is the longer one.
      expect(termScore('skrivebordet', 'skrivebord'), greaterThan(0.75));
      expect(termScore('telefonen', 'telefon'), greaterThan(0.75));
    });
  });
}
