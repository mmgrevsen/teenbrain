/// Where things are. Same idea as the object taxonomy, but for scenes.
///
/// A classifier's scene labels are a mix of *surfaces* ("desk", "table"),
/// *furniture* ("sofa", "bed") and *rooms* ("kitchen", "bedroom"). GlemtDet
/// prefers the most specific surface it can justify, and records how specific
/// that was so the answer can hedge honestly.
library;

import 'package:meta/meta.dart';

import 'object_taxonomy.dart' show normalizeLabel;

/// How precise a place label is. A room is a worse answer than a surface.
enum PlaceSpecificity {
  /// "Skrivebord", "Natbord" — you can walk up to it.
  surface,

  /// "Køkken", "Soveværelse" — narrows it to a room.
  room,

  /// "Bord", "Gulv" — true but nearly useless on its own.
  vague,
}

@immutable
class PlaceKind {
  const PlaceKind({
    required this.key,
    required this.label,
    required this.specificity,
    required this.exact,
    this.contains = const [],
    this.excludes = const [],
    this.weight = 1.0,
    this.minConfidence = 0.18,
    this.aliases = const [],
  });

  final String key;
  final String label;
  final PlaceSpecificity specificity;
  final List<String> exact;
  final List<String> contains;
  final List<String> excludes;

  /// Multiplier applied to the classifier confidence. Lets a strong signal
  /// like "desk" outweigh a weak one like "indoor".
  final double weight;

  final double minConfidence;

  /// Danish words the user might type.
  final List<String> aliases;
}

/// The places GlemtDet recognises.
///
/// As with the objects, every `exact` entry is a label Apple Vision really
/// emits. Three places from the brief are gone, because the vocabulary has no
/// word for them: there is no `nightstand`, no `floor`, `carpet` or `rug`, and
/// nothing for a windowsill. Listing them anyway would mean an answer that
/// could never be given.
const List<PlaceKind> kPlaceKinds = [
  PlaceKind(
    key: 'desk',
    label: 'Skrivebord',
    specificity: PlaceSpecificity.surface,
    weight: 1.25,
    exact: ['desk', 'cubicle'],
    excludes: ['desktop computer'],
    aliases: ['skrivebord', 'kontor', 'arbejdsbord', 'skrivebordet'],
  ),
  PlaceKind(
    key: 'bed',
    label: 'Seng',
    specificity: PlaceSpecificity.surface,
    weight: 1.2,
    exact: ['bed', 'bedding', 'bedroom', 'crib', 'pillow'],
    aliases: ['seng', 'soveværelse', 'sengen', 'dyne', 'pude'],
  ),
  PlaceKind(
    key: 'kitchen_counter',
    label: 'Køkkenbord',
    specificity: PlaceSpecificity.surface,
    weight: 1.25,
    exact: [
      'kitchen', 'kitchen_countertop', 'kitchen_room', 'kitchen_sink',
      'kitchen_oven', 'kitchen_faucet', 'stove', 'refrigerator', 'microwave',
      'dishwasher', 'oven', 'toaster', 'cutting_board',
    ],
    contains: ['kitchen'],
    aliases: ['køkken', 'køkkenbord', 'bordplade', 'komfur', 'køkkenbordet'],
  ),
  PlaceKind(
    key: 'sofa',
    label: 'Sofa',
    specificity: PlaceSpecificity.surface,
    weight: 1.2,
    exact: ['sofa', 'couch', 'living_room', 'armchair', 'chaise'],
    contains: ['living room'],
    aliases: ['sofa', 'stue', 'sofaen', 'lænestol'],
  ),
  PlaceKind(
    key: 'shelf',
    label: 'Reol',
    specificity: PlaceSpecificity.surface,
    weight: 1.2,
    exact: ['bookshelf', 'cabinet', 'closet'],
    aliases: ['reol', 'hylde', 'bogreol', 'skab'],
  ),
  PlaceKind(
    key: 'hallway',
    label: 'Entré',
    specificity: PlaceSpecificity.room,
    // "door" is the only signal Vision offers here, and a door shows up in
    // plenty of rooms — so it counts for less than a kitchen sink does.
    weight: 0.95,
    exact: ['door', 'porch', 'stairs'],
    excludes: ['doorbell', 'outdoor'],
    aliases: ['entré', 'gang', 'hall', 'ved døren', 'entre', 'entreen'],
  ),
  PlaceKind(
    key: 'bathroom',
    label: 'Badeværelse',
    specificity: PlaceSpecificity.room,
    weight: 1.1,
    exact: [
      'bathroom', 'bathroom_room', 'bathroom_faucet', 'shower', 'bath',
      'toilet_seat', 'washbasin', 'jacuzzi',
    ],
    contains: ['bathroom'],
    aliases: ['badeværelse', 'bad', 'toilet', 'badeværelset'],
  ),
  PlaceKind(
    key: 'dining_table',
    label: 'Spisebord',
    specificity: PlaceSpecificity.surface,
    weight: 1.15,
    exact: ['dining_room'],
    contains: ['dining'],
    aliases: ['spisebord', 'spisestue', 'spisebordet'],
  ),
  PlaceKind(
    key: 'bag',
    label: 'Taske',
    specificity: PlaceSpecificity.surface,
    weight: 1.1,
    exact: ['bag', 'backpack', 'briefcase', 'luggage', 'suitcase'],
    contains: ['backpack'],
    excludes: ['bagel'],
    aliases: ['taske', 'rygsæk', 'i tasken', 'tasken'],
  ),
  PlaceKind(
    key: 'car',
    label: 'Bil',
    specificity: PlaceSpecificity.room,
    weight: 1.1,
    exact: ['car', 'dashboard', 'car_seat'],
    excludes: ['carpet', 'cardboard', 'card', 'carton', 'carousel', 'carnival', 'carrot'],
    aliases: ['bil', 'i bilen', 'bilen'],
  ),
  PlaceKind(
    key: 'table',
    label: 'Bord',
    specificity: PlaceSpecificity.vague,
    weight: 0.85,
    // "tableware" is a plate; "cakestand" is not a table you leave keys on.
    exact: ['table'],
    excludes: ['tableware', 'vegetable', 'timetable', 'turntable', 'cutting board'],
    aliases: ['bord', 'bordet'],
  ),
  PlaceKind(
    key: 'chair',
    label: 'Stol',
    specificity: PlaceSpecificity.vague,
    weight: 0.85,
    exact: ['chair', 'chair_other', 'folding_chair', 'swivel_chair', 'stool', 'high_chair', 'seat'],
    // A chairlift is on a mountain.
    excludes: ['chairlift', 'wheelchair', 'chairman', 'armchair', 'car seat'],
    aliases: ['stol', 'stolen', 'skammel'],
  ),
  PlaceKind(
    key: 'garage',
    label: 'Garage',
    specificity: PlaceSpecificity.room,
    weight: 1.05,
    exact: ['garage', 'shed', 'workbench', 'toolbox'],
    aliases: ['garage', 'skur', 'værksted'],
  ),
  PlaceKind(
    key: 'outdoor',
    label: 'Udendørs',
    specificity: PlaceSpecificity.room,
    weight: 0.9,
    exact: ['balcony', 'patio', 'deck', 'garden', 'yard', 'terrace'],
    aliases: ['udenfor', 'altan', 'terrasse', 'have', 'udendørs'],
  ),
];

@immutable
class PlaceMatch {
  const PlaceMatch(this.kind, this.confidence, this.sourceLabel);
  final PlaceKind kind;

  /// Weighted confidence, clamped to 0..1.
  final double confidence;
  final String sourceLabel;
}

class PlaceTaxonomy {
  PlaceTaxonomy._(this._byExact, this.kinds);

  factory PlaceTaxonomy(List<PlaceKind> kinds) {
    final byExact = <String, PlaceKind>{};
    for (final kind in kinds) {
      for (final id in kind.exact) {
        byExact.putIfAbsent(normalizeLabel(id), () => kind);
      }
    }
    return PlaceTaxonomy._(byExact, List.unmodifiable(kinds));
  }

  static final PlaceTaxonomy standard = PlaceTaxonomy(kPlaceKinds);

  final Map<String, PlaceKind> _byExact;
  final List<PlaceKind> kinds;

  PlaceKind? kindByKey(String key) {
    for (final k in kinds) {
      if (k.key == key) return k;
    }
    return null;
  }

  PlaceMatch? match(String rawLabel, double confidence) {
    final norm = normalizeLabel(rawLabel);
    if (norm.isEmpty) return null;

    final exact = _byExact[norm];
    if (exact != null && !_vetoed(exact, norm)) {
      if (confidence < exact.minConfidence) return null;
      return PlaceMatch(exact, _clamp(confidence * exact.weight), rawLabel);
    }

    PlaceKind? best;
    for (final kind in kinds) {
      if (_vetoed(kind, norm)) continue;
      for (final needle in kind.contains) {
        if (norm.contains(normalizeLabel(needle))) {
          if (best == null || kind.weight > best.weight) best = kind;
          break;
        }
      }
    }
    if (best == null || confidence < best.minConfidence) return null;
    return PlaceMatch(best, _clamp(confidence * best.weight * 0.9), rawLabel);
  }

  bool _vetoed(PlaceKind kind, String norm) {
    for (final bad in kind.excludes) {
      if (norm.contains(normalizeLabel(bad))) return true;
    }
    return false;
  }

  static double _clamp(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
}
