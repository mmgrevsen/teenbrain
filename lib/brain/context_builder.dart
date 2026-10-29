/// Assembles the memory context for one request.
///
/// This is the piece that makes the memory system scalable. The model never
/// sees the database — it sees this, and this has a fixed token budget. A user
/// with twenty memories and a user with twenty thousand cost the same to serve.
///
/// Nothing here calls a model. Relevance is scored locally by [MemoryStore],
/// so building context is free and its cost does not grow with the archive.
library;

import '../core/danish.dart';
import '../domain/models/memory.dart';
import '../domain/models/profile.dart';
import '../domain/models/school.dart';
import '../domain/repositories/memory_store.dart';

/// How many tokens each part of the context may spend.
///
/// The numbers are deliberately small. A system prompt is paid for on every
/// single turn, so the question is never "what could be relevant" but "what
/// changes the answer".
class ContextBudget {
  const ContextBudget({
    this.profile = 150,
    this.preferences = 200,
    this.relevant = 600,
    this.temporal = 400,
    this.subject = 400,
  });

  /// Used when the request is background work the user never reads.
  const ContextBudget.minimal()
      : profile = 100,
        preferences = 100,
        relevant = 200,
        temporal = 0,
        subject = 100;

  final int profile;
  final int preferences;
  final int relevant;
  final int temporal;
  final int subject;

  int get total => profile + preferences + relevant + temporal + subject;
}

/// Everything the builder needs that is not memory.
class ContextSnapshot {
  const ContextSnapshot({
    required this.profile,
    this.subjects = const [],
    this.upcoming = const [],
    this.neglected = const [],
    this.recentActivity = const [],
    this.focusSubject,
  });

  final Profile? profile;
  final List<Subject> subjects;
  final List<Assignment> upcoming;

  /// Subjects untouched for a while, with how many days it has been.
  final List<({Subject subject, int days})> neglected;

  /// One line per recent thing the user did.
  final List<String> recentActivity;

  /// The subject the user is looking at, when there is one.
  final Subject? focusSubject;
}

class ContextBuilder {
  ContextBuilder(this._memories);

  final MemoryStore _memories;

  /// Danish averages close to four characters per token on this kind of text.
  /// An estimate is enough: the budget is a guardrail, not an invoice.
  static int estimateTokens(String text) => (text.length / 4).ceil();

  Future<MemoryContext> build({
    required String query,
    required ContextSnapshot snapshot,
    ContextBudget budget = const ContextBudget(),
  }) async {
    final terms = _termsOf(query);
    final candidates = await _memories.ranked(
      terms: terms,
      subjectId: snapshot.focusSubject?.id,
      limit: 60,
    );

    final sections = <String>[];
    final chosen = <Memory>[];

    // -- Who they are ---------------------------------------------------
    final profileLines = _profileLines(snapshot);
    if (profileLines.isNotEmpty) {
      sections.add('## Om brugeren\n${profileLines.join('\n')}');
    }

    // -- How they learn -------------------------------------------------
    // Preferences change how every answer should be written, so they get
    // their own budget rather than competing with topic recall.
    final preferences = _take(
      candidates.where((m) => m.kind == MemoryKind.preference),
      budget.preferences,
      chosen,
    );
    if (preferences.isNotEmpty) {
      sections.add('## Sådan lærer brugeren bedst\n${_bullets(preferences)}');
    }

    // -- What is relevant to the question --------------------------------
    final relevant = _take(
      candidates.where((m) => !chosen.contains(m)),
      budget.relevant,
      chosen,
    );
    if (relevant.isNotEmpty) {
      sections.add('## Relevant hukommelse\n${_bullets(relevant)}');
    }

    // -- What is going on right now --------------------------------------
    if (budget.temporal > 0) {
      final temporal = _temporalLines(snapshot);
      if (temporal.isNotEmpty) {
        final block = '## Lige nu\n${temporal.join('\n')}';
        if (estimateTokens(block) <= budget.temporal) {
          sections.add(block);
        } else {
          sections.add(_truncate(block, budget.temporal));
        }
      }
    }

    // -- The subject in focus ---------------------------------------------
    if (snapshot.focusSubject != null) {
      final subjectMemories = _take(
        candidates.where(
            (m) => !chosen.contains(m) && m.subjectId == snapshot.focusSubject!.id),
        budget.subject,
        chosen,
      );
      if (subjectMemories.isNotEmpty) {
        sections.add(
          '## Om ${snapshot.focusSubject!.name}\n${_bullets(subjectMemories)}',
        );
      }
    }

    final rendered = sections.join('\n\n');

    if (chosen.isNotEmpty) {
      await _memories.markUsed(chosen.map((m) => m.id).toList());
    }

    return MemoryContext(
      memories: chosen,
      rendered: rendered,
      estimatedTokens: estimateTokens(rendered),
      consideredCount: candidates.length,
    );
  }

  /// Fills a section up to its budget, in the order relevance gave them.
  List<Memory> _take(Iterable<Memory> source, int budget, List<Memory> chosen) {
    final taken = <Memory>[];
    var spent = 0;
    for (final memory in source) {
      final cost = estimateTokens(memory.promptLine) + 3;
      if (spent + cost > budget) continue;
      taken.add(memory);
      chosen.add(memory);
      spent += cost;
    }
    return taken;
  }

  List<String> _profileLines(ContextSnapshot snapshot) {
    final profile = snapshot.profile;
    final lines = <String>[];
    if (profile != null) {
      lines.add('- Navn: ${profile.displayName}');
      if (profile.gradeLevel != null) lines.add('- Klassetrin: ${profile.gradeLevel}');
    }
    if (snapshot.subjects.isNotEmpty) {
      lines.add('- Fag: ${snapshot.subjects.map((s) => s.name).join(', ')}');
    }
    return lines;
  }

  List<String> _temporalLines(ContextSnapshot snapshot) {
    final lines = <String>[];
    final now = DateTime.now();

    for (final assignment in snapshot.upcoming.take(4)) {
      final days = assignment.daysUntilDue(now);
      final when = switch (days) {
        null => '',
        < 0 => ' (overskredet)',
        0 => ' (i dag)',
        1 => ' (i morgen)',
        _ => ' (om $days dage)',
      };
      lines.add('- Opgave: ${assignment.title}$when');
    }

    for (final entry in snapshot.neglected.take(3)) {
      lines.add('- Har ikke arbejdet med ${entry.subject.name} i ${entry.days} dage');
    }

    for (final activity in snapshot.recentActivity.take(4)) {
      lines.add('- $activity');
    }

    return lines;
  }

  String _bullets(List<Memory> memories) =>
      memories.map((m) => '- ${m.promptLine}').join('\n');

  String _truncate(String text, int tokenBudget) {
    final maxChars = tokenBudget * 4;
    if (text.length <= maxChars) return text;
    final cut = text.substring(0, maxChars);
    final lastBreak = cut.lastIndexOf('\n');
    return lastBreak > 0 ? cut.substring(0, lastBreak) : cut;
  }

  /// Query terms, folded and stripped of words that carry no signal.
  static List<String> _termsOf(String query) {
    return foldDanish(query)
        .split(' ')
        .where((w) => w.length > 2 && !kStopWords.contains(w))
        .toList();
  }
}
