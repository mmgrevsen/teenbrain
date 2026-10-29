/// Danish language helpers.
///
/// Kept separate from the vision taxonomy on purpose: what an object *is* is a
/// computer-vision concern, how you say it in Danish is not. Adding a second
/// language later means adding a file next to this one, not editing the
/// detection pipeline.
library;

/// Grammatical gender, which decides din/dit/dine and den/det/de.
enum Gender { common, neuter, plural }

class ObjectGrammar {
  const ObjectGrammar(this.gender, {this.definite});

  final Gender gender;

  /// Definite form, e.g. "telefonen". Falls back to label + "en" when absent.
  final String? definite;

  /// "din" / "dit" / "dine"
  String get yourPossessive => switch (gender) {
        Gender.common => 'din',
        Gender.neuter => 'dit',
        Gender.plural => 'dine',
      };

  /// Subject form: "den" / "det" / "de" — as in "hvor **de** lå".
  String get subjectPronoun => switch (gender) {
        Gender.common => 'den',
        Gender.neuter => 'det',
        Gender.plural => 'de',
      };

  /// Object form: "den" / "det" / "dem" — as in "jeg fandt **dem**".
  String get objectPronoun => switch (gender) {
        Gender.common => 'den',
        Gender.neuter => 'det',
        Gender.plural => 'dem',
      };

  /// "er" agreement is the same, but "lå"/"lå" is too — kept for clarity.
  String get wasVerb => 'lå';
}

const Map<String, ObjectGrammar> kObjectGrammar = {
  'phone': ObjectGrammar(Gender.common, definite: 'telefonen'),
  'computer': ObjectGrammar(Gender.common, definite: 'computeren'),
  'headphones': ObjectGrammar(Gender.plural, definite: 'høretelefonerne'),
  'bag': ObjectGrammar(Gender.common, definite: 'tasken'),
  'wallet': ObjectGrammar(Gender.common, definite: 'pungen'),
  'bottle': ObjectGrammar(Gender.common, definite: 'vandflasken'),
  'book': ObjectGrammar(Gender.common, definite: 'bogen'),
  'controller': ObjectGrammar(Gender.common, definite: 'controlleren'),
  'glasses': ObjectGrammar(Gender.plural, definite: 'brillerne'),
  'clothing': ObjectGrammar(Gender.neuter, definite: 'tøjet'),
  'shoes': ObjectGrammar(Gender.plural, definite: 'skoene'),
  'watch': ObjectGrammar(Gender.neuter, definite: 'uret'),
  'mouse': ObjectGrammar(Gender.common, definite: 'musen'),
  'cup': ObjectGrammar(Gender.common, definite: 'koppen'),
  'umbrella': ObjectGrammar(Gender.common, definite: 'paraplyen'),
  'pen': ObjectGrammar(Gender.common, definite: 'pennen'),
  'cable': ObjectGrammar(Gender.common, definite: 'ledningen'),
  'camera': ObjectGrammar(Gender.neuter, definite: 'kameraet'),
  'passport': ObjectGrammar(Gender.neuter, definite: 'passet'),
};

ObjectGrammar grammarFor(String objectKey) =>
    kObjectGrammar[objectKey] ?? const ObjectGrammar(Gender.common);

/// "dine AirPods", "din telefon"
String yourObject(String objectKey, String label) =>
    '${grammarFor(objectKey).yourPossessive} ${_lowerFirstUnlessProper(label)}';

String _lowerFirstUnlessProper(String label) {
  // A brand name keeps its capitalisation ("AirPods"); an ordinary noun does
  // not ("Telefon" → "telefon"). The tell is an interior capital letter.
  if (label.isEmpty) return label;
  final interior = label.substring(1);
  if (interior != interior.toLowerCase()) return label;
  return label[0].toLowerCase() + interior;
}

class PlaceGrammar {
  const PlaceGrammar(this.preposition, this.definite, {this.indefinite});

  /// "på" or "i"
  final String preposition;

  /// "skrivebordet"
  final String definite;

  /// "et bord" — used when GlemtDet is not sure which one.
  final String? indefinite;

  /// "på skrivebordet". Some places are their own adverb ("udendørs") and
  /// carry no preposition at all.
  String get located => preposition.isEmpty ? definite : '$preposition $definite';

  /// "på et bord"
  String get locatedVague {
    if (indefinite == null) return located;
    return preposition.isEmpty ? indefinite! : '$preposition $indefinite';
  }
}

const Map<String, PlaceGrammar> kPlaceGrammar = {
  'desk': PlaceGrammar('på', 'skrivebordet', indefinite: 'et skrivebord'),
  'bed': PlaceGrammar('i', 'sengen', indefinite: 'en seng'),
  'kitchen_counter': PlaceGrammar('på', 'køkkenbordet', indefinite: 'et køkkenbord'),
  'sofa': PlaceGrammar('i', 'sofaen', indefinite: 'en sofa'),
  'shelf': PlaceGrammar('i', 'reolen', indefinite: 'en reol'),
  'hallway': PlaceGrammar('i', 'entréen', indefinite: 'en entré'),
  'bathroom': PlaceGrammar('på', 'badeværelset', indefinite: 'et badeværelse'),
  'dining_table': PlaceGrammar('på', 'spisebordet', indefinite: 'et spisebord'),
  'bag': PlaceGrammar('i', 'tasken', indefinite: 'en taske'),
  'car': PlaceGrammar('i', 'bilen', indefinite: 'en bil'),
  'table': PlaceGrammar('på', 'bordet', indefinite: 'et bord'),
  'chair': PlaceGrammar('på', 'stolen', indefinite: 'en stol'),
  'garage': PlaceGrammar('i', 'garagen', indefinite: 'en garage'),
  'outdoor': PlaceGrammar('', 'udendørs', indefinite: 'udendørs'),
};

PlaceGrammar? placeGrammarFor(String? placeKey) =>
    placeKey == null ? null : kPlaceGrammar[placeKey];

/// Folds Danish characters so "noegler", "nøgler" and "NØGLER" all match.
String foldDanish(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    switch (rune) {
      case 0xE6: // æ
        buffer.write('ae');
      case 0xF8: // ø
        buffer.write('oe');
      case 0xE5: // å
        buffer.write('aa');
      case 0xE9: // é
      case 0xE8: // è
        buffer.write('e');
      default:
        final ch = String.fromCharCode(rune);
        final isWord = (rune >= 97 && rune <= 122) || (rune >= 48 && rune <= 57);
        buffer.write(isWord ? ch : ' ');
    }
  }
  return buffer.toString().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
}

/// Danish words that carry no search signal.
const Set<String> kStopWords = {
  'hvor', 'er', 'mine', 'min', 'mit', 'jeg', 'har', 'du', 'set', 'hvornaar',
  'saa', 'lagde', 'laa', 'ligger', 'den', 'det', 'de', 'et', 'en', 'paa', 'i',
  'til', 'og', 'sidst', 'seneste', 'sidste', 'hvad', 'med', 'af', 'om', 'for',
  'kan', 'finde', 'ved', 'nogen', 'noget', 'mon', 'lige', 'nu', 'egentlig',
  'lagt', 'gemt', 'blev', 'var', 'hen', 'henne', 'sted', 'steder',
};
