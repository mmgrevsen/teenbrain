/// Turning "Hvor er mine AirPods?" into a truthful Danish sentence.
library;

import '../models/observation.dart';

/// What the user asked, after parsing.
class ParsedQuery {
  const ParsedQuery({
    required this.raw,
    required this.intent,
    this.objectKey,
    this.objectLabel,
    this.placeKey,
    this.matchScore = 0,
  });

  final String raw;
  final QueryIntent intent;

  /// Canonical object the user seems to mean, if one was recognised.
  final String? objectKey;
  final String? objectLabel;

  /// Set for "hvad ligger på skrivebordet?"-style questions.
  final String? placeKey;

  /// 0..1 confidence in the object match. Low scores make the answer hedge.
  final double matchScore;
}

enum QueryIntent {
  /// "Hvor er mine AirPods?"
  whereIsObject,

  /// "Hvornår så jeg min telefon?"
  whenWasObject,

  /// "Hvad ligger på skrivebordet?"
  whatIsAtPlace,

  /// "Hvad har du set?" / anything else.
  general,
}

/// A complete answer, kept structured so the UI can render evidence next to
/// the sentence instead of trusting prose alone.
class MemoryAnswer {
  const MemoryAnswer({
    required this.text,
    required this.query,
    this.primary,
    this.supporting = const [],
    this.habit,
    this.isConfident = true,
    this.caveat,
  });

  /// The short, natural Danish sentence shown to the user.
  final String text;

  final ParsedQuery query;

  /// The observation the answer is based on, if any.
  final Observation? primary;

  /// Earlier sightings shown as context.
  final List<Observation> supporting;

  /// Learned habit worth mentioning ("ligger oftest på skrivebordet").
  final PlaceHabit? habit;

  /// False when GlemtDet is guessing; the UI marks these visibly.
  final bool isConfident;

  /// A known limitation of the vision backend behind this answer — shown next
  /// to it so a confident sentence does not overstate what the model can
  /// actually tell apart.
  final String? caveat;
}

/// Implementations may be purely local (the default) or delegate to a model.
/// The contract is the same, so the app never depends on which is in use.
abstract class AnswerEngine {
  String get engineId;

  ParsedQuery parse(String input);

  Future<MemoryAnswer> answer(String input);
}
