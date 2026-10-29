/// The things GlemtDet is asked about but genuinely cannot see.
///
/// Every vision backend has holes, and the honest thing is to name them. Apple
/// Vision's classifier has 1303 categories and not one of them is a key — so
/// searching for "nøgler" must not answer *"jeg har ikke set dine nøgler endnu"*,
/// which implies it simply has not happened to spot them yet. It never will.
///
/// This list is verified against the backend's real vocabulary by
/// `test/vocabulary_coverage_test.dart`, so it cannot quietly go stale: if a
/// future model does learn keys, that test fails and tells you to remove the
/// entry.
library;

import 'package:meta/meta.dart';

@immutable
class BlindSpot {
  const BlindSpot({
    required this.key,
    required this.label,
    required this.aliases,
    required this.explanation,
  });

  /// Not an [ObjectKind] key — nothing is ever stored under it. It exists so
  /// the search can recognise the word and answer truthfully.
  final String key;

  final String label;

  /// Danish words the user might type.
  final List<String> aliases;

  /// Shown verbatim. Says what cannot be done and why.
  final String explanation;
}

/// Measured against Apple Vision's `VNClassifyImageRequest` vocabulary.
const List<BlindSpot> kAppleVisionBlindSpots = [
  BlindSpot(
    key: 'keys',
    label: 'Nøgler',
    aliases: ['nøgler', 'nøgle', 'nøglering', 'husnøgle', 'bilnøgle', 'nøglebundt'],
    explanation:
        'Jeg kan ikke genkende nøgler. Den lokale model på denne Mac kender '
        '1303 kategorier, og nøgler er ikke en af dem — så jeg vil aldrig se '
        'dem, uanset hvor længe scanneren kører.',
  ),
  BlindSpot(
    key: 'charger',
    label: 'Oplader',
    aliases: ['oplader', 'ladekabel', 'strømforsyning', 'adapter'],
    explanation:
        'Jeg kan ikke kende forskel på en oplader og en hvilken som helst '
        'anden ledning. Hvis jeg har set en ledning, står den under “Ledning”.',
  ),
  BlindSpot(
    key: 'tablet',
    label: 'Tablet',
    aliases: ['tablet', 'ipad', 'e-reader', 'læseplade'],
    explanation:
        'Jeg kan ikke genkende en tablet. Den lokale model har ingen kategori '
        'for det, og forveksler den typisk med en skærm eller en telefon.',
  ),
];

/// Facts GlemtDet knows about a kind it *can* see, but only partly. Shown next
/// to an answer so the user is not misled by a confident sentence.
const Map<String, String> kBackendCaveats = {
  'headphones':
      'Den lokale model skelner ikke mellem AirPods, ørepropper og store '
      'hovedtelefoner — alt sammen står som “Høretelefoner”.',
  'cable':
      'Modellen ser en ledning, men ikke hvad den lader op.',
};

BlindSpot? blindSpotFor(String folded, List<BlindSpot> spots) {
  for (final spot in spots) {
    for (final alias in spot.aliases) {
      if (folded.contains(_fold(alias))) return spot;
    }
  }
  return null;
}

String _fold(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    switch (rune) {
      case 0xE6:
        buffer.write('ae');
      case 0xF8:
        buffer.write('oe');
      case 0xE5:
        buffer.write('aa');
      default:
        final isWord = (rune >= 97 && rune <= 122) || (rune >= 48 && rune <= 57);
        buffer.write(isWord ? String.fromCharCode(rune) : ' ');
    }
  }
  return buffer.toString().trim();
}
