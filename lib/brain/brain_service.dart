/// The app's one entry point to intelligence.
///
/// Screens call this. It owns the order of operations that every AI feature
/// shares: gather context, build a prompt under budget, call the model,
/// persist what came back, and write a timeline entry so the work is visible
/// afterwards. Nothing here knows which provider is behind [AiClient].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ai/anthropic_client.dart';
import '../core/time_format.dart';
import '../domain/models/chat.dart';
import '../domain/models/memory.dart';
import '../domain/models/note.dart';
import '../domain/models/quiz.dart';
import '../domain/models/school.dart';
import '../domain/models/search.dart';
import '../domain/models/timeline.dart';
import '../domain/repositories/chat_repository.dart';
import '../domain/repositories/memory_store.dart';
import '../domain/repositories/note_repository.dart';
import '../domain/repositories/profile_repository.dart';
import '../domain/repositories/quiz_repository.dart';
import '../domain/repositories/school_repository.dart';
import '../domain/repositories/search_index.dart';
import '../domain/repositories/timeline_repository.dart';
import '../domain/services/ai_client.dart';
import 'brain_tools.dart';
import 'context_builder.dart';
import 'prompts.dart';
import 'schemas.dart';
import 'search_interpreter.dart';

class BrainService {
  BrainService({
    required this.client,
    required this.profiles,
    required this.school,
    required this.notes,
    required this.chats,
    required this.quizzes,
    required this.timeline,
    required this.memories,
    required this.search,
    required this.memoryEnabled,
  })  : _context = ContextBuilder(memories),
        _tools = BrainTools(
          school: school,
          notes: notes,
          search: search,
          timeline: timeline,
          memories: memories,
        );

  final AiClient client;
  final ProfileRepository profiles;
  final SchoolRepository school;
  final NoteRepository notes;
  final ChatRepository chats;
  final QuizRepository quizzes;
  final TimelineRepository timeline;
  final MemoryStore memories;
  final SearchIndex search;

  /// The user's "AI memory" switch. When off, nothing is retrieved and nothing
  /// is written — the assistant works, but statelessly.
  final bool Function() memoryEnabled;

  final ContextBuilder _context;
  final BrainTools _tools;

  bool get isConfigured => client.isConfigured;
  String get unconfiguredReason => client.unconfiguredReason;

  // ------------------------------------------------------------------ chat

  /// Streams a reply and persists both turns.
  ///
  /// The user's message is written before the request goes out, so a dropped
  /// connection loses the answer but never the question.
  Stream<AiDelta> chat({
    required int conversationId,
    required String message,
    Subject? focusSubject,
  }) async* {
    await chats.addMessage(
      conversationId: conversationId,
      role: ChatRole.user,
      content: message,
    );

    final memory = await buildContext(query: message, focusSubject: focusSubject);
    final history = await chats.messages(conversationId);

    final request = AiRequest(
      system: Prompts.chat(memory),
      messages: [
        for (final m in history.where((m) => m.role != ChatRole.system))
          m.role == ChatRole.user
              ? AiMessage.user(m.content)
              : AiMessage.assistant(m.content),
      ],
      tools: _tools.all(),
      maxTokens: 4096,
    );

    final answer = StringBuffer();
    final used = <String>[];
    var failed = false;

    await for (final delta in client.complete(request)) {
      switch (delta) {
        case AiTextDelta(:final text):
          answer.write(text);
        case AiToolDelta(:final toolName):
          used.add(toolName);
        case AiFailure():
          failed = true;
        case AiDone():
          break;
      }
      yield delta;
    }

    if (failed || answer.isEmpty) return;

    await chats.addMessage(
      conversationId: conversationId,
      role: ChatRole.assistant,
      content: answer.toString(),
      toolCalls: used.toSet().toList(),
    );

    final conversation = await chats.conversation(conversationId);
    if (conversation != null && conversation.title == 'Ny samtale') {
      await chats.renameConversation(conversationId, _titleFrom(message));
    }

    await timeline.record(
      kind: TimelineKind.chat,
      title: conversation?.title ?? _titleFrom(message),
      summary: message.length > 120 ? '${message.substring(0, 120)}…' : message,
      subjectId: focusSubject?.id,
      refTable: 'conversations',
      refId: conversationId,
    );

    // Learning from the conversation happens after the user has their answer,
    // and is never allowed to break the turn.
    unawaited(_learnFrom(conversationId, message, answer.toString()));
  }

  String _titleFrom(String message) {
    final flat = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= 48) return flat;
    return '${flat.substring(0, 48).trim()}…';
  }

  // -------------------------------------------------------------- context

  /// Exposed so the My AI page can show exactly what would be sent.
  Future<MemoryContext> buildContext({
    required String query,
    Subject? focusSubject,
    ContextBudget budget = const ContextBudget(),
  }) async {
    if (!memoryEnabled()) return const MemoryContext.empty();

    final now = DateTime.now();
    final subjects = await school.subjects();
    final touched = await timeline.lastTouchedPerSubject();

    final neglected = <({Subject subject, int days})>[];
    for (final subject in subjects) {
      final last = touched[subject.id];
      final days = last == null ? null : now.difference(last).inDays;
      if (days != null && days >= 3) {
        neglected.add((subject: subject, days: days));
      }
    }
    neglected.sort((a, b) => b.days.compareTo(a.days));

    final recent = await timeline.events(
      after: now.subtract(const Duration(days: 3)),
      limit: 6,
    );

    return _context.build(
      query: query,
      budget: budget,
      snapshot: ContextSnapshot(
        profile: await profiles.read(),
        subjects: subjects,
        upcoming: await school.upcoming(limit: 5),
        neglected: neglected,
        recentActivity: [
          for (final e in recent) '${e.kind.label}: ${e.title}',
        ],
        focusSubject: focusSubject,
      ),
    );
  }

  // ---------------------------------------------------------- suggestions

  /// The dashboard's "Hvad skal vi fokusere på?".
  ///
  /// Returns an empty list rather than throwing: the dashboard has to render
  /// with or without a working model.
  Future<List<FocusSuggestion>> suggestions() async {
    if (!client.isConfigured) return const [];

    try {
      final memory = await buildContext(query: 'hvad skal jeg lave nu');
      return await client.structured(
        AiRequest(
          system: Prompts.suggestions(memory),
          messages: [
            const AiMessage.user(
              'Hvad skal jeg fokusere på lige nu? Brug kun det, du ved om mig.',
            ),
          ],
          maxTokens: 1024,
        ),
        Schemas.suggestions,
      );
    } catch (e) {
      debugPrint('Kunne ikke hente forslag: $e');
      return const [];
    }
  }

  // ----------------------------------------------------------------- quiz

  /// Builds a quiz and stores it. Throws [AiFailure] so the UI can explain why.
  Future<Quiz> generateQuiz({
    required String title,
    int? subjectId,
    int? topicId,
    required QuizSource source,
    int questionCount = 8,
    Set<QuestionKind> kinds = const {
      QuestionKind.multipleChoice,
      QuestionKind.trueFalse,
      QuestionKind.shortAnswer,
    },
  }) async {
    final subject = subjectId == null ? null : await school.subject(subjectId);
    final topic = topicId == null ? null : await school.topic(topicId);
    final material = await _materialFor(source, subjectId: subjectId, topicId: topicId);

    if (material.trim().isEmpty) {
      throw const AiFailure(
        'Der er ikke noget materiale at lave en quiz ud fra endnu. '
        'Skriv en note eller vælg et emne først.',
        kind: AiFailureKind.badRequest,
      );
    }

    final memory = await buildContext(
      query: '${subject?.name ?? ''} ${topic?.name ?? ''} quiz',
      focusSubject: subject,
      budget: const ContextBudget.minimal(),
    );

    final wanted = kinds.map((k) => k.label).join(', ');
    final questions = await client.structured(
      AiRequest(
        system: '${Prompts.quiz}\n\n${memory.rendered}',
        messages: [
          AiMessage.user(
            'Lav $questionCount spørgsmål om '
            '${topic?.name ?? subject?.name ?? title}.\n'
            'Brug disse typer: $wanted.\n\n'
            'Materiale:\n$material',
          ),
        ],
        maxTokens: 4096,
        effort: AiEffort.medium,
      ),
      Schemas.quiz,
    );

    final quiz = await quizzes.create(
      title: title,
      subjectId: subjectId,
      topicId: topicId,
      sourceKind: source.code,
      questions: questions,
    );

    await timeline.record(
      kind: TimelineKind.quiz,
      title: 'Quiz lavet: ${quiz.title}',
      subjectId: subjectId,
      refTable: 'quizzes',
      refId: quiz.id,
    );

    return quiz;
  }

  Future<String> _materialFor(QuizSource source, {int? subjectId, int? topicId}) async {
    switch (source) {
      case QuizSource.notes:
        return notes.corpusFor(subjectId: subjectId, topicId: topicId);

      case QuizSource.mistakes:
        final mistakes = await quizzes.recentMistakes(subjectId: subjectId);
        if (mistakes.isEmpty) return '';
        return mistakes
            .map((q) => '- ${q.prompt}\n  Rigtigt svar: ${q.answer}')
            .join('\n');

      case QuizSource.topic:
        final topic = topicId == null ? null : await school.topic(topicId);
        final subject = subjectId == null ? null : await school.subject(subjectId);
        final corpus = await notes.corpusFor(subjectId: subjectId, topicId: topicId);
        final heading = 'Emne: ${topic?.name ?? '—'}\nFag: ${subject?.name ?? '—'}';
        return corpus.isEmpty ? heading : '$heading\n\n$corpus';
    }
  }

  /// Grades a free-text answer. Falls back to a strict local comparison when
  /// there is no model, rather than marking everything wrong.
  Future<GradedAnswer> gradeAnswer({
    required QuizQuestion question,
    required String given,
  }) async {
    final normalisedGiven = given.trim().toLowerCase();
    final normalisedAnswer = question.answer.trim().toLowerCase();

    if (!question.kind.needsAiGrading || !client.isConfigured) {
      final correct = normalisedGiven == normalisedAnswer;
      return GradedAnswer(
        correct: correct,
        feedback: correct ? '' : 'Det rigtige svar er: ${question.answer}',
      );
    }

    if (normalisedGiven.isEmpty) {
      return GradedAnswer(
        correct: false,
        feedback: 'Du svarede ikke. Det rigtige svar er: ${question.answer}',
      );
    }

    try {
      return await client.structured(
        AiRequest(
          system: Prompts.grading,
          messages: [
            AiMessage.user(
              'Spørgsmål: ${question.prompt}\n'
              'Facit: ${question.answer}\n'
              'Elevens svar: $given',
            ),
          ],
          maxTokens: 512,
          model: AnthropicModels.background,
        ),
        Schemas.grading,
      );
    } catch (e) {
      debugPrint('Kunne ikke rette svaret: $e');
      final correct = normalisedGiven == normalisedAnswer;
      return GradedAnswer(
        correct: correct,
        feedback: correct ? '' : 'Det rigtige svar er: ${question.answer}',
      );
    }
  }

  // ---------------------------------------------------------------- notes

  /// Turns raw text into a structured note and saves it.
  Future<Note> structureNote({
    required String rawText,
    int? subjectId,
    String? sourceLabel,
  }) async {
    if (rawText.trim().length < 20) {
      throw const AiFailure(
        'Der er for lidt tekst til at lave en note ud af.',
        kind: AiFailureKind.badRequest,
      );
    }

    final subjects = await school.subjects();
    final structured = await client.structured(
      AiRequest(
        system: '${Prompts.notes}\n\n'
            'Brugerens fag: ${subjects.map((s) => s.name).join(', ')}',
        messages: [AiMessage.user(rawText)],
        maxTokens: 4096,
        effort: AiEffort.medium,
      ),
      Schemas.note,
    );

    final resolved = subjectId != null
        ? await school.subject(subjectId)
        : structured.subjectName == null
            ? null
            : await school.subjectByName(structured.subjectName!);

    final note = await notes.create(
      title: structured.title,
      bodyMd: structured.bodyMd,
      subjectId: resolved?.id,
      source: NoteSource.ai,
    );

    await timeline.record(
      kind: TimelineKind.note,
      title: note.title,
      summary: sourceLabel ?? 'Note struktureret af AI',
      subjectId: resolved?.id,
      refTable: 'notes',
      refId: note.id,
    );

    return note;
  }

  // --------------------------------------------------------------- memory

  /// Reads a finished exchange and stores whatever is worth keeping.
  ///
  /// Runs on the cheap model, after the answer, and swallows its own errors:
  /// failing to learn something must never look like a failed reply.
  Future<void> _learnFrom(int conversationId, String question, String answer) async {
    if (!memoryEnabled() || !client.isConfigured) return;

    try {
      final candidates = await client.structured(
        AiRequest(
          system: Prompts.extraction,
          messages: [
            AiMessage.user('Bruger: $question\n\nAssistent: $answer'),
          ],
          maxTokens: 1024,
          model: AnthropicModels.background,
        ),
        Schemas.memories,
      );

      for (final candidate in candidates) {
        final subject = candidate.subjectName == null
            ? null
            : await school.subjectByName(candidate.subjectName!);
        await memories.remember(
          candidate,
          source: MemorySource.inferred,
          subjectId: subject?.id,
          link: MemoryLink(refTable: 'conversations', refId: conversationId),
        );
      }
    } catch (e) {
      debugPrint('Kunne ikke udlede hukommelse: $e');
    }
  }

  /// Records what a finished quiz says about the user.
  ///
  /// Entirely local — a wrong answer is a measurement, not something that needs
  /// a model to interpret.
  Future<void> learnFromQuiz(Quiz quiz, QuizAttempt attempt) async {
    if (!memoryEnabled()) return;

    final subject = quiz.subjectId == null ? null : await school.subject(quiz.subjectId!);
    final topic = quiz.topicId == null ? null : await school.topic(quiz.topicId!);
    final label = topic?.name ?? quiz.title;

    if (topic != null) {
      await school.recordMastery(topic.id, attempt.ratio);
    }

    final wrong = attempt.answers.where((a) => !a.correct).toList();

    if (wrong.isNotEmpty) {
      final prompts = <String>[];
      for (final answer in wrong) {
        final question = quiz.questions.where((q) => q.id == answer.questionId).firstOrNull;
        if (question != null) prompts.add(question.prompt);
      }

      await memories.remember(
        MemoryCandidate(
          kind: MemoryKind.struggle,
          key: 'struggle.${_slug(subject?.name)}.${_slug(label)}',
          value: 'Har svært ved $label'
              '${subject == null ? '' : ' i ${subject.name}'} — '
              '${wrong.length} af ${attempt.total} forkert '
              '(${prompts.take(2).join('; ')})',
          confidence: (wrong.length / attempt.total).clamp(0.3, 0.9),
        ),
        source: MemorySource.quiz,
        subjectId: subject?.id,
        link: MemoryLink(refTable: 'quizzes', refId: quiz.id),
      );
    } else if (attempt.total >= 4) {
      await memories.remember(
        MemoryCandidate(
          kind: MemoryKind.strength,
          key: 'strength.${_slug(subject?.name)}.${_slug(label)}',
          value: 'Er god til $label${subject == null ? '' : ' i ${subject.name}'} — '
              'alle rigtige i en quiz med ${attempt.total} spørgsmål',
          confidence: 0.7,
        ),
        source: MemorySource.quiz,
        subjectId: subject?.id,
        link: MemoryLink(refTable: 'quizzes', refId: quiz.id),
      );
    }

    await memories.remember(
      MemoryCandidate(
        kind: MemoryKind.learning,
        key: 'topic.${_slug(subject?.name)}.${_slug(label)}',
        value: 'Har arbejdet med $label${subject == null ? '' : ' i ${subject.name}'}',
        confidence: 0.8,
      ),
      source: MemorySource.quiz,
      subjectId: subject?.id,
    );
  }

  static String _slug(String? text) {
    if (text == null || text.trim().isEmpty) return 'general';
    return text
        .toLowerCase()
        .replaceAll('æ', 'ae')
        .replaceAll('ø', 'oe')
        .replaceAll('å', 'aa')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  // --------------------------------------------------------------- search

  /// Global search. Works with or without a model — interpretation is local.
  Future<SearchOutcome> globalSearch(String query, {Set<SearchScope>? scopes}) async {
    if (query.trim().isEmpty) return const SearchOutcome.empty();

    final subjects = await school.subjects();
    final interpreter = SearchInterpreter(
      subjectNames: subjects.map((s) => s.name).toList(),
    );
    final interpretation = interpreter.interpret(query);

    final hits = await search.query(interpretation, scopes: scopes);

    return SearchOutcome(
      hits: hits,
      interpretation: interpretation,
      answer: _directAnswer(interpretation, hits),
    );
  }

  /// "Hvornår lærte jeg om fotosyntese?" deserves a date, not just a list.
  String? _directAnswer(SearchInterpretation interpretation, List<SearchHit> hits) {
    if (hits.isEmpty) return null;

    if (interpretation.wantsWhen) {
      final oldest = hits.reduce((a, b) => a.occurredAt.isBefore(b.occurredAt) ? a : b);
      final subject = oldest.subjectName == null ? '' : ' i ${oldest.subjectName}';
      final day = dayHeading(oldest.occurredAt);
      return 'Første gang var ${day[0].toLowerCase()}${day.substring(1)}'
          '$subject — ${oldest.title}.';
    }

    if (interpretation.wantsDifficulty) {
      final struggles = hits.where((h) => h.scope == SearchScope.memory).toList();
      if (struggles.isNotEmpty) {
        return struggles.take(3).map((h) => h.title).join('\n');
      }
    }

    return null;
  }
}

/// Where a quiz's questions come from.
enum QuizSource { topic, notes, mistakes }

extension QuizSourceCodec on QuizSource {
  String get code => switch (this) {
        QuizSource.topic => 'topic',
        QuizSource.notes => 'note',
        QuizSource.mistakes => 'mistakes',
      };

  String get label => switch (this) {
        QuizSource.topic => 'Emnet',
        QuizSource.notes => 'Mine noter',
        QuizSource.mistakes => 'Mine tidligere fejl',
      };
}
