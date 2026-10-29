/// What the app knows about the user.
///
/// A memory is one small, editable, attributable claim. It is deliberately not
/// a blob of prose: the user has to be able to read it, disagree with it and
/// switch it off, and the retrieval layer has to be able to score it.
library;

import 'package:meta/meta.dart';

enum MemoryKind { fact, learning, preference, struggle, strength }

extension MemoryKindCodec on MemoryKind {
  String get code => name;

  String get label => switch (this) {
        MemoryKind.fact => 'Fakta',
        MemoryKind.learning => 'Læring',
        MemoryKind.preference => 'Præference',
        MemoryKind.struggle => 'Svært',
        MemoryKind.strength => 'Stærk',
      };

  /// How the My AI page groups them.
  String get sectionTitle => switch (this) {
        MemoryKind.fact => 'Om dig',
        MemoryKind.learning => 'Det du har arbejdet med',
        MemoryKind.preference => 'Sådan lærer du bedst',
        MemoryKind.struggle => 'Det du har svært ved',
        MemoryKind.strength => 'Det du er god til',
      };

  static MemoryKind parse(String? code) => switch (code) {
        'learning' => MemoryKind.learning,
        'preference' => MemoryKind.preference,
        'struggle' => MemoryKind.struggle,
        'strength' => MemoryKind.strength,
        _ => MemoryKind.fact,
      };
}

enum MemorySource { onboarding, inferred, quiz, userEdit, session }

extension MemorySourceCodec on MemorySource {
  String get code => switch (this) {
        MemorySource.userEdit => 'user_edit',
        _ => name,
      };

  /// Shown on the My AI page so nothing the app claims is unattributable.
  String get label => switch (this) {
        MemorySource.onboarding => 'Du fortalte mig det',
        MemorySource.inferred => 'Jeg lagde mærke til det',
        MemorySource.quiz => 'Målt i en quiz',
        MemorySource.userEdit => 'Du rettede det',
        MemorySource.session => 'Set i en session',
      };

  /// Things the user stated outright are not up for revision by inference.
  bool get isAuthoritative => this == MemorySource.onboarding || this == MemorySource.userEdit;

  static MemorySource parse(String? code) => switch (code) {
        'onboarding' => MemorySource.onboarding,
        'quiz' => MemorySource.quiz,
        'user_edit' => MemorySource.userEdit,
        'session' => MemorySource.session,
        _ => MemorySource.inferred,
      };
}

@immutable
class Memory {
  const Memory({
    required this.id,
    required this.kind,
    required this.key,
    required this.value,
    this.confidence = 0.5,
    this.source = MemorySource.inferred,
    this.subjectId,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
    this.useCount = 0,
    this.pinned = false,
    this.active = true,
  });

  final int id;
  final MemoryKind kind;

  /// A stable slug — `grade_level`, `struggle.math.quadratics`. Uniqueness is
  /// on (kind, key), so re-learning the same thing updates instead of piling up.
  final String key;

  /// One sentence, in the user's language, written to be read by the user.
  final String value;

  final double confidence;
  final MemorySource source;
  final int? subjectId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;

  /// How often this memory has actually made it into a prompt. Feeds relevance.
  final int useCount;

  /// Pinned memories are always in context, budget permitting.
  final bool pinned;

  /// The user's off switch. An inactive memory keeps its row and its
  /// provenance, and never enters a prompt.
  final bool active;

  /// How the line reads inside a system prompt.
  String get promptLine => value;

  Memory copyWith({
    String? value,
    double? confidence,
    MemorySource? source,
    int? subjectId,
    bool clearSubject = false,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    int? useCount,
    bool? pinned,
    bool? active,
  }) =>
      Memory(
        id: id,
        kind: kind,
        key: key,
        value: value ?? this.value,
        confidence: confidence ?? this.confidence,
        source: source ?? this.source,
        subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        useCount: useCount ?? this.useCount,
        pinned: pinned ?? this.pinned,
        active: active ?? this.active,
      );
}

/// Where a memory came from, so the My AI page can show its receipts.
@immutable
class MemoryLink {
  const MemoryLink({required this.refTable, required this.refId});
  final String refTable;
  final int refId;
}

/// A memory the model proposed but that has not been written yet.
@immutable
class MemoryCandidate {
  const MemoryCandidate({
    required this.kind,
    required this.key,
    required this.value,
    this.confidence = 0.5,
    this.subjectName,
  });

  final MemoryKind kind;
  final String key;
  final String value;
  final double confidence;

  /// The model names subjects, it does not know their ids.
  final String? subjectName;
}

/// The bundle of memory assembled for one request, under a token budget.
///
/// This is what makes the memory system scalable: the model never sees the
/// database, only this.
@immutable
class MemoryContext {
  const MemoryContext({
    required this.memories,
    required this.rendered,
    required this.estimatedTokens,
    required this.consideredCount,
  });

  const MemoryContext.empty()
      : memories = const [],
        rendered = '',
        estimatedTokens = 0,
        consideredCount = 0;

  /// The memories that made the cut, in the order they were rendered.
  final List<Memory> memories;

  /// The block of text spliced into the system prompt.
  final String rendered;

  final int estimatedTokens;

  /// How many were weighed to pick these. Shown in the debug panel so the
  /// "we don't send everything" claim is visible rather than asserted.
  final int consideredCount;

  bool get isEmpty => memories.isEmpty;
}
