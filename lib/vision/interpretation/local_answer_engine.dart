/// GlemtDet's search and answer layer.
///
/// This runs entirely on the machine: a Danish query is folded, stripped of
/// stop words, matched against the object vocabulary (exact, prefix and
/// edit-distance), and turned into a sentence built from what the database
/// actually contains. No text leaves the computer and nothing is invented — if
/// there is no observation, the answer says so.
///
/// It implements [AnswerEngine], so a model-backed engine can replace it later
/// without touching the UI.
library;

import '../../core/danish.dart';
import '../../core/fuzzy.dart';
import '../../core/time_format.dart';
import '../../domain/models/observation.dart';
import '../../domain/repositories/memory_repository.dart';
import '../../domain/services/answer_engine.dart';
import '../taxonomy/blind_spots.dart';
import '../taxonomy/object_taxonomy.dart';
import '../taxonomy/place_taxonomy.dart';

class LocalAnswerEngine implements AnswerEngine {
  LocalAnswerEngine(
    this._repository, {
    ObjectTaxonomy? objects,
    PlaceTaxonomy? places,
    List<BlindSpot>? blindSpots,
  })  : _objects = objects ?? ObjectTaxonomy.standard,
        _places = places ?? PlaceTaxonomy.standard,
        _blindSpots = blindSpots ?? kAppleVisionBlindSpots;

  final MemoryRepository _repository;
  final ObjectTaxonomy _objects;
  final PlaceTaxonomy _places;

  /// What the running backend genuinely cannot see. Consulted before the
  /// database, because "jeg har ikke set dine nøgler endnu" would be a lie:
  /// it implies the scanner might find them tomorrow.
  final List<BlindSpot> _blindSpots;

  @override
  String get engineId => 'local_danish_v1';

  /// Exposed so the UI can show live suggestions while typing.
  List<ObjectKind> get knownKinds => _objects.kinds;

  // ------------------------------------------------------------- parsing

  @override
  ParsedQuery parse(String input) {
    final folded = foldDanish(input);
    final intent = _intentOf(folded);
    final objectHit = _matchObject(folded);
    final placeHit = _matchPlace(folded);

    return ParsedQuery(
      raw: input.trim(),
      intent: intent == QueryIntent.general && objectHit != null
          ? QueryIntent.whereIsObject
          : intent,
      objectKey: objectHit?.key,
      objectLabel: objectHit?.label,
      placeKey: placeHit,
      matchScore: objectHit?.score ?? 0,
    );
  }

  QueryIntent _intentOf(String folded) {
    if (folded.contains('hvornaar') || folded.contains('hvor laenge')) {
      return QueryIntent.whenWasObject;
    }
    if (folded.startsWith('hvad') || folded.contains('hvad ligger') || folded.contains('hvad er der')) {
      return QueryIntent.whatIsAtPlace;
    }
    if (folded.contains('hvor') || folded.contains('har du set') || folded.contains('hvorhenne')) {
      return QueryIntent.whereIsObject;
    }
    return QueryIntent.general;
  }

  _ObjectHit? _matchObject(String folded) {
    final tokens = folded.split(' ').where((t) => t.isNotEmpty && !kStopWords.contains(t)).toList();

    _ObjectHit? best;
    void offer(String key, String label, double score) {
      if (score <= 0) return;
      if (best == null || score > best!.score) best = _ObjectHit(key, label, score);
    }

    for (final kind in _objects.kinds) {
      // Whole-phrase aliases ("apple watch") are checked against the full
      // query, single-word ones against each remaining token.
      for (final alias in [kind.label, ...kind.aliases]) {
        final a = foldDanish(alias);
        if (a.isEmpty) continue;
        if (a.contains(' ')) {
          if (folded.contains(a)) offer(kind.key, kind.label, 1.0);
          continue;
        }
        for (final token in tokens) {
          offer(kind.key, kind.label, termScore(token, a));
        }
      }
    }
    return best;
  }

  String? _matchPlace(String folded) {
    String? bestKey;
    var bestScore = 0.0;
    for (final kind in _places.kinds) {
      for (final alias in [kind.label, ...kind.aliases]) {
        final a = foldDanish(alias);
        if (a.isEmpty) continue;
        if (a.contains(' ')) {
          if (folded.contains(a) && 1.0 > bestScore) {
            bestScore = 1.0;
            bestKey = kind.key;
          }
          continue;
        }
        for (final token in folded.split(' ')) {
          final s = termScore(token, a);
          if (s > bestScore) {
            bestScore = s;
            bestKey = kind.key;
          }
        }
      }
    }
    return bestScore >= 0.75 ? bestKey : null;
  }

  // ------------------------------------------------------------ answering

  @override
  Future<MemoryAnswer> answer(String input) async {
    final query = parse(input);

    if (query.raw.isEmpty) {
      return MemoryAnswer(
        text: 'Skriv hvad du leder efter — for eksempel “Hvor er mine AirPods?”.',
        query: query,
        isConfident: false,
      );
    }

    if (query.intent == QueryIntent.whatIsAtPlace && query.placeKey != null) {
      return _answerPlace(query);
    }

    // A word the backend can never recognise is answered before anything else,
    // so the user is told it is impossible rather than left waiting for the
    // scanner to eventually catch it.
    final blind = blindSpotFor(foldDanish(query.raw), _blindSpots);
    if (blind != null && (query.objectKey == null || query.matchScore < 0.99)) {
      return MemoryAnswer(
        text: blind.explanation,
        query: query,
        isConfident: false,
      );
    }

    if (query.objectKey == null) {
      return _answerUnknownObject(query);
    }

    final observations = await _repository.observationsFor(query.objectKey!, limit: 12);
    if (observations.isEmpty) {
      return _answerNeverSeen(query);
    }

    final latest = observations.first;
    final habits = await _repository.habitsFor(query.objectKey!);
    final habit = habits.isNotEmpty && habits.first.isStrong ? habits.first : null;

    if (query.intent == QueryIntent.whenWasObject) {
      return _answerWhen(query, latest, observations, habit);
    }
    return _answerWhere(query, latest, observations, habit);
  }

  Future<MemoryAnswer> _answerPlace(ParsedQuery query) async {
    final observations = await _repository.history(
      HistoryFilter(placeKey: query.placeKey, limit: 40),
    );
    final grammar = placeGrammarFor(query.placeKey);
    final where = grammar?.located ?? 'der';

    if (observations.isEmpty) {
      return MemoryAnswer(
        text: 'Jeg har ikke set noget $where endnu.',
        query: query,
        isConfident: false,
      );
    }

    // Newest sighting per object, so the answer is a list of things, not rows.
    final seen = <String, Observation>{};
    for (final o in observations) {
      seen.putIfAbsent(o.objectKey, () => o);
    }
    final items = seen.values.take(5).toList();
    final names = items.map((o) => yourObject(o.objectKey, o.objectLabel)).toList();

    return MemoryAnswer(
      text: 'Senest $where så jeg ${_joinDanish(names)}. '
          'Sidste gang var ${whenPhrase(items.first.seenAt)}.',
      query: query,
      primary: items.first,
      supporting: items.skip(1).toList(),
      isConfident: true,
    );
  }

  Future<MemoryAnswer> _answerUnknownObject(ParsedQuery query) async {
    final tracked = await _repository.objects();
    if (tracked.isEmpty) {
      return MemoryAnswer(
        text: 'Jeg har ikke set noget endnu. Åbn scanneren og lad GlemtDet '
            'kigge på dine omgivelser, så begynder hukommelsen at fyldes.',
        query: query,
        isConfident: false,
      );
    }
    final examples = tracked.take(3).map((o) => o.label).join(', ');
    return MemoryAnswer(
      text: 'Jeg er ikke sikker på hvad du leder efter. Jeg husker blandt andet '
          '$examples — prøv at skrive et af dem.',
      query: query,
      isConfident: false,
    );
  }

  Future<MemoryAnswer> _answerNeverSeen(ParsedQuery query) async {
    final name = yourObject(query.objectKey!, query.objectLabel!);
    return MemoryAnswer(
      text: 'Jeg har ikke set $name endnu. Der er ingen observationer i hukommelsen.',
      query: query,
      isConfident: false,
      caveat: kBackendCaveats[query.objectKey!],
    );
  }

  Future<MemoryAnswer> _answerWhen(
    ParsedQuery query,
    Observation latest,
    List<Observation> all,
    PlaceHabit? habit,
  ) async {
    final name = yourObject(latest.objectKey, latest.objectLabel);
    final grammar = placeGrammarFor(latest.placeKey);
    final buffer = StringBuffer('Jeg så $name ${whenPhrase(latest.seenAt)}');
    if (grammar != null && latest.placeCertainty != PlaceCertainty.unknown) {
      buffer.write(' ${grammar.located}');
    }
    buffer.write('.');

    return MemoryAnswer(
      text: buffer.toString(),
      query: query,
      primary: latest,
      supporting: all.skip(1).take(3).toList(),
      habit: habit,
      isConfident: true,
      caveat: kBackendCaveats[latest.objectKey],
    );
  }

  Future<MemoryAnswer> _answerWhere(
    ParsedQuery query,
    Observation latest,
    List<Observation> all,
    PlaceHabit? habit,
  ) async {
    final name = yourObject(latest.objectKey, latest.objectLabel);
    final grammar = placeGrammarFor(latest.placeKey);
    final when = whenPhrase(latest.seenAt);
    final neighbours = await _neighbours(latest);
    final sentences = <String>[];

    switch (latest.placeCertainty) {
      case PlaceCertainty.confident when grammar != null:
        final beside = neighbours.isEmpty
            ? ''
            : ' ved siden af ${yourObject(neighbours.first.objectKey, neighbours.first.objectLabel)}';
        sentences.add('Jeg så $name ${grammar.located}$beside $when.');

      case PlaceCertainty.approximate when grammar != null:
        sentences.add(
          'Jeg så $name ${grammar.locatedVague} $when, '
          'men jeg kunne ikke afgøre præcis hvilket rum.',
        );

      case PlaceCertainty.confident:
      case PlaceCertainty.approximate:
      case PlaceCertainty.unknown:
        sentences.add(
          'Jeg så $name $when, men jeg kunne ikke se hvor '
          '${grammarFor(latest.objectKey).subjectPronoun} lå.',
        );
    }

    final caveat = stalenessCaveat(latest.seenAt);
    if (caveat.isNotEmpty) sentences.add(caveat);

    if (habit != null && habit.placeKey != latest.placeKey) {
      final habitGrammar = placeGrammarFor(habit.placeKey);
      if (habitGrammar != null) {
        sentences.add('Normalt ligger ${grammarFor(latest.objectKey).subjectPronoun} '
            '${habitGrammar.located}.');
      }
    }

    final confident = latest.placeCertainty == PlaceCertainty.confident &&
        DateTime.now().difference(latest.seenAt).inHours < 24;

    return MemoryAnswer(
      text: sentences.join(' '),
      query: query,
      primary: latest,
      supporting: all.skip(1).take(3).toList(),
      habit: habit,
      isConfident: confident,
      caveat: kBackendCaveats[latest.objectKey],
    );
  }

  /// Other objects captured in the same reference frame — the basis for
  /// "ved siden af din computer".
  Future<List<Observation>> _neighbours(Observation observation) async {
    final nearby = await _repository.around(
      observation.seenAt,
      window: const Duration(seconds: 3),
      excludeId: observation.id,
    );
    return nearby
        .where((o) =>
            o.objectKey != observation.objectKey &&
            (observation.imagePath == null || o.imagePath == observation.imagePath))
        .toList();
  }

  static String _joinDanish(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} og ${items.last}';
  }
}

class _ObjectHit {
  _ObjectHit(this.key, this.label, this.score);
  final String key;
  final String label;
  final double score;
}
