/// The tools the assistant can reach the user's own data with.
///
/// This is what separates TeenBrain from a chat window: asked "hvad lavede jeg
/// med matematik i sidste uge?", the model looks it up instead of inventing a
/// plausible week.
///
/// Every tool returns text, never throws, and never writes anything the user
/// cannot see and undo afterwards.
library;

import '../core/time_format.dart';
import '../domain/models/memory.dart';
import '../domain/models/note.dart';
import '../domain/models/school.dart';
import '../domain/models/search.dart';
import '../domain/models/timeline.dart';
import '../domain/repositories/memory_store.dart';
import '../domain/repositories/note_repository.dart';
import '../domain/repositories/school_repository.dart';
import '../domain/repositories/search_index.dart';
import '../domain/repositories/timeline_repository.dart';
import '../domain/services/ai_client.dart';

class BrainTools {
  BrainTools({
    required this.school,
    required this.notes,
    required this.search,
    required this.timeline,
    required this.memories,
  });

  final SchoolRepository school;
  final NoteRepository notes;
  final SearchIndex search;
  final TimelineRepository timeline;
  final MemoryStore memories;

  /// The full set, for the chat assistant.
  List<AiTool> all() => [
        searchNotes,
        subjectStatus,
        schedule,
        createNote,
        remember,
      ];

  /// Read-only subset, for background work that must not write.
  List<AiTool> readOnly() => [searchNotes, subjectStatus, schedule];

  // ------------------------------------------------------------------ read

  AiTool get searchNotes => AiTool(
        name: 'search_notes',
        description:
            'Søg i brugerens egne noter, samtaler, quizzer og aktivitetshistorik. '
            'Brug det, når brugeren spørger om noget, de har lavet eller skrevet før.',
        parameters: const {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Ordene der skal søges på. Ikke hele spørgsmålet.',
            },
            'subject': {
              'type': 'string',
              'description': 'Valgfrit fagnavn at afgrænse til, fx "Matematik".',
            },
          },
          'required': ['query'],
        },
        run: (args) async {
          final query = '${args['query'] ?? ''}'.trim();
          if (query.isEmpty) return 'Ingen søgeord angivet.';

          final hits = await search.query(
            SearchInterpretation(terms: query.split(RegExp(r'\s+'))),
            limit: 8,
          );
          if (hits.isEmpty) return 'Ingen resultater for "$query".';

          final wanted = '${args['subject'] ?? ''}'.trim();
          final filtered = wanted.isEmpty
              ? hits
              : hits.where((h) => h.subjectName?.toLowerCase() == wanted.toLowerCase()).toList();
          final shown = filtered.isEmpty ? hits : filtered;

          return shown
              .map((h) => '[${h.scope.label}] ${h.title} '
                  '(${dayHeading(h.occurredAt)})\n${h.snippet}')
              .join('\n\n');
        },
      );

  AiTool get subjectStatus => AiTool(
        name: 'get_subject_status',
        description:
            'Hent status for et fag: emner, hvor stærkt brugeren står i hvert, '
            'åbne opgaver, tid brugt den seneste uge og quiz-resultater. '
            'Uden fagnavn returneres alle fag kort.',
        parameters: const {
          'type': 'object',
          'properties': {
            'subject': {
              'type': 'string',
              'description': 'Fagets navn. Udelad for at få alle fag.',
            },
          },
        },
        run: (args) async {
          final wanted = '${args['subject'] ?? ''}'.trim();

          if (wanted.isEmpty) {
            final all = await school.summaries();
            if (all.isEmpty) return 'Brugeren har ikke oprettet nogen fag endnu.';
            return all.map(_shortSummary).join('\n');
          }

          final subject = await school.subjectByName(wanted);
          if (subject == null) {
            final names = (await school.subjects()).map((s) => s.name).join(', ');
            return 'Faget "$wanted" findes ikke. '
                '${names.isEmpty ? 'Der er ingen fag endnu.' : 'Brugeren har: $names.'}';
          }

          final summary = await school.summary(subject.id);
          if (summary == null) return 'Kunne ikke hente status for $wanted.';
          return _fullSummary(summary);
        },
      );

  AiTool get schedule => AiTool(
        name: 'get_schedule',
        description:
            'Hent kommende opgaver med deadline og de seneste aktiviteter. '
            'Brug det til spørgsmål som "hvad skal jeg lave i dag?".',
        parameters: const {'type': 'object', 'properties': {}},
        run: (args) async {
          final now = DateTime.now();
          final upcoming = await school.upcoming(limit: 8);
          final recent = await timeline.events(
            after: now.subtract(const Duration(days: 3)),
            limit: 10,
          );

          final buffer = StringBuffer();

          if (upcoming.isEmpty) {
            buffer.writeln('Ingen opgaver med deadline.');
          } else {
            buffer.writeln('Kommende opgaver:');
            for (final a in upcoming) {
              final days = a.daysUntilDue(now);
              final when = switch (days) {
                null => 'ingen dato',
                < 0 => 'overskredet med ${-days} dage',
                0 => 'i dag',
                1 => 'i morgen',
                _ => 'om $days dage',
              };
              final estimate =
                  a.estimatedMinutes == null ? '' : ', ca. ${a.estimatedMinutes} min';
              buffer.writeln('- ${a.title} ($when$estimate)');
            }
          }

          if (recent.isNotEmpty) {
            buffer.writeln('\nSeneste aktivitet:');
            for (final e in recent) {
              buffer.writeln('- ${e.title} (${whenPhrase(e.startedAt)})');
            }
          }

          return buffer.toString().trim();
        },
      );

  // ----------------------------------------------------------------- write

  AiTool get createNote => AiTool(
        name: 'create_note',
        description:
            'Gem en note i brugerens noter. Brug det kun, når brugeren beder om '
            'at få noget gemt — ikke for at gemme dine egne svar.',
        parameters: const {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'Kort titel.'},
            'body': {'type': 'string', 'description': 'Indholdet, som markdown.'},
            'subject': {'type': 'string', 'description': 'Valgfrit fagnavn.'},
          },
          'required': ['title', 'body'],
        },
        run: (args) async {
          final title = '${args['title'] ?? ''}'.trim();
          final body = '${args['body'] ?? ''}';
          if (title.isEmpty) return 'En note skal have en titel.';

          final subjectName = '${args['subject'] ?? ''}'.trim();
          final subject =
              subjectName.isEmpty ? null : await school.subjectByName(subjectName);

          final note = await notes.create(
            title: title,
            bodyMd: body,
            subjectId: subject?.id,
            source: NoteSource.ai,
          );
          await timeline.record(
            kind: TimelineKind.note,
            title: note.title,
            summary: 'Note gemt af AI',
            subjectId: subject?.id,
            refTable: 'notes',
            refId: note.id,
          );
          return 'Noten "${note.title}" er gemt${subject == null ? '' : ' under ${subject.name}'}.';
        },
      );

  AiTool get remember => AiTool(
        name: 'remember',
        description:
            'Gem noget varigt om brugeren, som skal påvirke fremtidige svar — '
            'fx at de foretrækker korte forklaringer, eller at de har svært ved '
            'et bestemt emne. Gem ikke selve samtalen.',
        parameters: const {
          'type': 'object',
          'properties': {
            'kind': {
              'type': 'string',
              'enum': ['fact', 'learning', 'preference', 'struggle', 'strength'],
              'description': 'Hvilken slags viden det er.',
            },
            'key': {
              'type': 'string',
              'description': 'Stabil engelsk slug, fx "struggle.math.quadratics".',
            },
            'value': {
              'type': 'string',
              'description': 'Én sætning på dansk, som brugeren selv kan læse.',
            },
            'subject': {'type': 'string', 'description': 'Valgfrit fagnavn.'},
          },
          'required': ['kind', 'key', 'value'],
        },
        run: (args) async {
          final value = '${args['value'] ?? ''}'.trim();
          final key = '${args['key'] ?? ''}'.trim();
          if (value.isEmpty || key.isEmpty) return 'Både nøgle og indhold skal udfyldes.';

          final subjectName = '${args['subject'] ?? ''}'.trim();
          final subject =
              subjectName.isEmpty ? null : await school.subjectByName(subjectName);

          await memories.remember(
            MemoryCandidate(
              kind: MemoryKindCodec.parse('${args['kind']}'),
              key: key,
              value: value,
              confidence: 0.7,
            ),
            source: MemorySource.inferred,
            subjectId: subject?.id,
          );
          return 'Husket: $value';
        },
      );

  // --------------------------------------------------------------- shaping

  String _shortSummary(SubjectSummary s) {
    final parts = <String>[
      s.subject.name,
      if (s.topics.isNotEmpty) '${s.topics.length} emner',
      if (s.openAssignments.isNotEmpty) '${s.openAssignments.length} åbne opgaver',
      if (s.minutesLast7Days > 0) '${s.minutesLast7Days} min sidste uge',
      if (s.lastStudied != null) 'sidst ${whenPhrase(s.lastStudied!)}',
    ];
    return '- ${parts.join(' · ')}';
  }

  String _fullSummary(SubjectSummary s) {
    final buffer = StringBuffer('${s.subject.name}\n');

    void listTopics(String heading, List<Topic> topics) {
      if (topics.isEmpty) return;
      buffer.writeln('$heading: ${topics.map((t) => t.name).join(', ')}');
    }

    listTopics('Aktuelt', s.current);
    listTopics('Mangler træning', s.needsWork);
    listTopics('Stærk', s.strong);

    if (s.openAssignments.isNotEmpty) {
      buffer.writeln('Åbne opgaver: ${s.openAssignments.map((a) => a.title).join(', ')}');
    }
    if (s.minutesLast7Days > 0) {
      buffer.writeln('Tid sidste uge: ${s.minutesLast7Days} minutter');
    }
    if (s.questionsAnswered > 0) {
      buffer.writeln(
        'Quiz: ${s.questionsCorrect}/${s.questionsAnswered} rigtige '
        '(${((s.accuracy ?? 0) * 100).round()} %)',
      );
    }
    if (s.lastStudied != null) {
      buffer.writeln('Sidst arbejdet med: ${whenPhrase(s.lastStudied!)}');
    }

    final text = buffer.toString().trim();
    return text == s.subject.name
        ? '${s.subject.name}: ingen aktivitet registreret endnu.'
        : text;
  }
}
