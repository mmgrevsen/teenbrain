/// Maps a vision backend's native vocabulary onto the objects GlemtDet talks
/// about in Danish.
///
/// Backends disagree wildly about names: Apple Vision says `eyeglasses`, a COCO
/// model says `cell phone`, ML Kit says `Fashion good`. Everything downstream
/// only ever sees an [ObjectKind]. This file is the single translation point.
///
/// Matching is done on a *normalised* identifier (lowercased, every non-letter
/// collapsed to a single space) so `computer_keyboard`, `computer keyboard` and
/// `Computer-Keyboard` all behave identically.
library;

import 'package:meta/meta.dart';

@immutable
class ObjectKind {
  const ObjectKind({
    required this.key,
    required this.label,
    required this.icon,
    required this.exact,
    this.contains = const [],
    this.excludes = const [],
    this.minConfidence = 0.28,
    this.priority = 0,
    this.aliases = const [],
  });

  /// Canonical key stored in the database. Never translated.
  final String key;

  /// Danish display name.
  final String label;

  /// A single glyph used in lists. Kept text-only to stay crisp at any size.
  final String icon;

  /// Backend identifiers that map here outright.
  final List<String> exact;

  /// Substrings that also map here, checked against the normalised identifier.
  final List<String> contains;

  /// Substrings that veto a match (e.g. "bag" must not match "bagel").
  final List<String> excludes;

  /// Labels below this are ignored — some categories are noisier than others.
  final double minConfidence;

  /// When two kinds match the same label, the higher priority wins.
  /// Specific kinds (AirPods) must outrank generic ones (headset).
  final int priority;

  /// Danish words the user might type when searching for this object.
  final List<String> aliases;
}

String normalizeLabel(String raw) {
  final buffer = StringBuffer();
  var lastWasSpace = true;
  for (final rune in raw.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final isWord = (rune >= 97 && rune <= 122) || (rune >= 48 && rune <= 57);
    if (isWord) {
      buffer.write(ch);
      lastWasSpace = false;
    } else if (!lastWasSpace) {
      buffer.write(' ');
      lastWasSpace = true;
    }
  }
  return buffer.toString().trim();
}

/// The objects from the brief, plus the near-neighbours a real classifier will
/// actually emit for them.
/// The objects GlemtDet tracks.
///
/// Every `exact` entry below is a label Apple Vision can actually emit — this
/// list was written against a dump of its 1303-category vocabulary, not from
/// guesses, and `test/vocabulary_coverage_test.dart` fails if any kind loses
/// its coverage. The `excludes` are the traps that dump revealed: `thermostat`
/// is not a thermos, `iron_clothing` is an appliance rather than a garment,
/// and `chairlift` is not somewhere you leave your glasses.
///
/// Three things from the brief are absent on purpose — keys, chargers and
/// tablets. Vision has no category for any of them. They live in
/// `blind_spots.dart` instead, so a search says so out loud.
const List<ObjectKind> kObjectKinds = [
  ObjectKind(
    key: 'phone',
    label: 'Telefon',
    icon: '▭',
    priority: 30,
    // Exact only: half the vocabulary ends in "phone" — saxophone, megaphone,
    // payphone, xylophone, headphones — and none of them is a mobile.
    exact: ['phone'],
    aliases: ['telefon', 'mobil', 'iphone', 'smartphone', 'mobiltelefon'],
  ),
  ObjectKind(
    key: 'computer',
    label: 'Computer',
    icon: '▤',
    priority: 25,
    exact: [
      'laptop', 'computer', 'computer_keyboard', 'computer_monitor',
      'computer_tower', 'monitor', 'television',
    ],
    contains: ['laptop', 'computer'],
    excludes: ['computer mouse'],
    aliases: ['computer', 'mac', 'macbook', 'pc', 'bærbar', 'laptop', 'skærm', 'tastatur'],
  ),
  ObjectKind(
    key: 'headphones',
    label: 'Høretelefoner',
    icon: '⌾',
    priority: 25,
    // Vision has exactly one label here. It cannot tell AirPods from a pair of
    // studio cans, so GlemtDet does not pretend to either — see kBackendCaveats.
    exact: ['headphones'],
    aliases: [
      'høretelefoner', 'hovedtelefoner', 'headset', 'airpods', 'ørepropper',
      'øretelefoner', 'earbuds', 'propper', 'bøjle',
    ],
  ),
  ObjectKind(
    key: 'bag',
    label: 'Taske',
    icon: '▣',
    priority: 20,
    exact: ['bag', 'backpack', 'briefcase', 'luggage', 'suitcase', 'sack', 'paper_bag'],
    contains: ['backpack', 'briefcase'],
    excludes: ['bagel', 'sleeping bag'],
    aliases: ['taske', 'rygsæk', 'skoletaske', 'computertaske', 'pose', 'kuffert'],
  ),
  ObjectKind(
    key: 'wallet',
    label: 'Pung',
    icon: '▬',
    priority: 30,
    exact: ['wallet', 'purse'],
    aliases: ['pung', 'tegnebog', 'portemonnæ', 'kortholder'],
  ),
  ObjectKind(
    key: 'bottle',
    label: 'Vandflaske',
    icon: '⌷',
    priority: 20,
    exact: ['bottle', 'thermos', 'jug'],
    // "thermostat" starts with "thermos" and is a wall panel.
    excludes: ['wine bottle', 'thermostat'],
    aliases: ['vandflaske', 'flaske', 'drikkedunk', 'dunk', 'termokande'],
  ),
  ObjectKind(
    key: 'book',
    label: 'Bog',
    icon: '▥',
    priority: 15,
    // Exact only, so "bookshelf" stays a place rather than becoming a book.
    exact: ['book', 'magazine', 'newspaper', 'checkbook', 'printed_page', 'document'],
    aliases: ['bog', 'bøger', 'notesbog', 'blad', 'magasin', 'avis'],
  ),
  ObjectKind(
    key: 'controller',
    label: 'Controller',
    icon: '⬡',
    priority: 30,
    exact: ['gamepad', 'joystick'],
    aliases: ['controller', 'gamepad', 'fjernbetjening', 'joystick', 'playstation', 'xbox'],
  ),
  ObjectKind(
    key: 'glasses',
    label: 'Briller',
    icon: '◠',
    priority: 30,
    exact: ['eyeglasses', 'sunglasses', 'goggles'],
    contains: ['eyeglass', 'sunglass'],
    aliases: ['briller', 'brille', 'solbriller', 'læsebriller'],
  ),
  ObjectKind(
    key: 'clothing',
    label: 'Tøj',
    icon: '⊓',
    priority: 10,
    exact: [
      'clothing', 'jacket', 'hoodie', 'suit', 'scarf', 'sock', 'hat', 'beanie',
      'glove', 'glove_other', 'mitten', 'jeans', 'kimono', 'kilt', 'gown',
      'apron', 'bathrobe', 'necktie', 'bowtie', 'poncho', 'tuxedo', 'sari',
      'swimsuit', 'wetsuit', 'leotard', 'lab_coat', 'cloak', 'sunhat',
      'cowboy_hat', 'baseball_hat', 'fedora', 'sombrero', 'headgear',
    ],
    // "iron_clothing" is the appliance, not the shirt.
    excludes: ['iron clothing', 'clothesline', 'clothespin'],
    aliases: ['tøj', 'trøje', 'jakke', 'bukser', 'skjorte', 'hue', 'halstørklæde', 'sok'],
  ),
  ObjectKind(
    key: 'shoes',
    label: 'Sko',
    icon: '◺',
    priority: 25,
    exact: [
      'shoes', 'sneaker', 'boot', 'sandal', 'footwear', 'high_heel', 'loafer',
      'moccasin', 'ski_boot', 'flipper',
    ],
    excludes: ['horseshoe', 'snowshoe'],
    aliases: ['sko', 'sneakers', 'støvler', 'sandaler', 'hjemmesko'],
  ),
  ObjectKind(
    key: 'watch',
    label: 'Ur',
    icon: '◔',
    priority: 25,
    // "clock" is on a wall; only a watch is something you put down and lose.
    exact: ['watch', 'timepiece'],
    excludes: ['watchdog', 'watchtower'],
    aliases: ['ur', 'armbåndsur', 'smartwatch', 'apple watch'],
  ),
  ObjectKind(
    key: 'mouse',
    label: 'Mus',
    icon: '◗',
    priority: 30,
    exact: ['computer_mouse'],
    excludes: ['mousetrap'],
    aliases: ['mus', 'computermus', 'trackpad'],
  ),
  ObjectKind(
    key: 'cup',
    label: 'Kop',
    icon: '⌯',
    priority: 15,
    exact: ['cup', 'mug', 'teapot'],
    excludes: ['cupboard', 'cupcake'],
    aliases: ['kop', 'krus', 'kaffekop', 'tekande'],
  ),
  ObjectKind(
    key: 'umbrella',
    label: 'Paraply',
    icon: '⌂',
    priority: 25,
    exact: ['umbrella'],
    aliases: ['paraply'],
  ),
  ObjectKind(
    key: 'pen',
    label: 'Pen',
    icon: '⌇',
    priority: 20,
    exact: ['pen'],
    aliases: ['pen', 'kuglepen', 'blyant', 'tusch'],
  ),
  ObjectKind(
    key: 'cable',
    label: 'Ledning',
    icon: '⌁',
    priority: 20,
    // The closest Vision gets to a charger. Named for what it can actually
    // tell you, not for what you were hoping to find.
    exact: ['cord'],
    aliases: ['ledning', 'kabel', 'usb', 'snor'],
  ),
  ObjectKind(
    key: 'camera',
    label: 'Kamera',
    icon: '◎',
    priority: 25,
    exact: ['camera', 'binoculars'],
    aliases: ['kamera', 'fotoapparat', 'kikkert'],
  ),
  ObjectKind(
    key: 'passport',
    label: 'Pas',
    icon: '▢',
    priority: 30,
    exact: ['passport', 'ticket', 'credit_card'],
    aliases: ['pas', 'billet', 'kort', 'kreditkort', 'dankort'],
  ),
];

/// Result of mapping one backend label.
@immutable
class ObjectMatch {
  const ObjectMatch(this.kind, this.confidence, this.sourceLabel);
  final ObjectKind kind;
  final double confidence;
  final String sourceLabel;
}

class ObjectTaxonomy {
  ObjectTaxonomy._(this._byExact, this.kinds);

  factory ObjectTaxonomy(List<ObjectKind> kinds) {
    final byExact = <String, List<ObjectKind>>{};
    for (final kind in kinds) {
      for (final id in kind.exact) {
        byExact.putIfAbsent(normalizeLabel(id), () => []).add(kind);
      }
    }
    for (final list in byExact.values) {
      list.sort((a, b) => b.priority.compareTo(a.priority));
    }
    return ObjectTaxonomy._(byExact, List.unmodifiable(kinds));
  }

  static final ObjectTaxonomy standard = ObjectTaxonomy(kObjectKinds);

  final Map<String, List<ObjectKind>> _byExact;
  final List<ObjectKind> kinds;

  ObjectKind? kindByKey(String key) {
    for (final k in kinds) {
      if (k.key == key) return k;
    }
    return null;
  }

  /// Maps a single backend label. Returns null when the label is not something
  /// GlemtDet tracks — which is the common case and not an error.
  ObjectMatch? match(String rawLabel, double confidence) {
    final norm = normalizeLabel(rawLabel);
    if (norm.isEmpty) return null;

    final exactHits = _byExact[norm];
    if (exactHits != null) {
      for (final kind in exactHits) {
        if (_vetoed(kind, norm)) continue;
        if (confidence < kind.minConfidence) return null;
        return ObjectMatch(kind, confidence, rawLabel);
      }
    }

    ObjectKind? best;
    for (final kind in kinds) {
      if (_vetoed(kind, norm)) continue;
      var hit = false;
      for (final needle in kind.contains) {
        if (norm.contains(normalizeLabel(needle))) {
          hit = true;
          break;
        }
      }
      if (!hit) continue;
      if (best == null || kind.priority > best.priority) best = kind;
    }
    if (best == null) return null;
    if (confidence < best.minConfidence) return null;
    // Substring matches are inherently weaker evidence than exact ones.
    return ObjectMatch(best, confidence * 0.9, rawLabel);
  }

  bool _vetoed(ObjectKind kind, String norm) {
    for (final bad in kind.excludes) {
      if (norm.contains(normalizeLabel(bad))) return true;
    }
    return false;
  }

  /// Labels from [vocabulary] that no kind claims. Used by the diagnostics
  /// screen to check the mapping against what the backend can actually say.
  List<String> unmapped(List<String> vocabulary) =>
      vocabulary.where((l) => match(l, 1.0) == null).toList();

  /// Labels a given kind would claim out of [vocabulary]. Verifies that e.g.
  /// `keys` really does have something to match on this machine.
  List<String> coverageFor(String key, List<String> vocabulary) =>
      vocabulary.where((l) => match(l, 1.0)?.kind.key == key).toList();
}
