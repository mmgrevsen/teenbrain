/// Typed shapes the model must produce.
///
/// Each of these is enforced by the API through forced tool use, so a malformed
/// answer is a parse error here rather than nonsense in the database.
library;

import '../domain/models/memory.dart';
import '../domain/models/quiz.dart';
import '../domain/services/ai_client.dart';

/// One suggestion on the dashboard.
class FocusSuggestion {
  const FocusSuggestion({
    required this.title,
    required this.reason,
    this.action = SuggestionAction.none,
    this.subjectName,
    this.topicName,
  });

  final String title;
  final String reason;
  final SuggestionAction action;
  final String? subjectName;
  final String? topicName;
}

/// What the card's button does. The model picks; the app decides whether it
/// can honour it, so a suggestion never produces a dead button.
enum SuggestionAction { none, startFocus, makeQuiz, openSubject, openChat }

extension SuggestionActionCodec on SuggestionAction {
  static SuggestionAction parse(String? code) => switch (code) {
        'start_focus' => SuggestionAction.startFocus,
        'make_quiz' => SuggestionAction.makeQuiz,
        'open_subject' => SuggestionAction.openSubject,
        'open_chat' => SuggestionAction.openChat,
        _ => SuggestionAction.none,
      };
}

/// A note the model structured out of raw text.
class StructuredNote {
  const StructuredNote({required this.title, required this.bodyMd, this.subjectName});

  final String title;
  final String bodyMd;
  final String? subjectName;
}

/// How a free-text answer was graded.
class GradedAnswer {
  const GradedAnswer({required this.correct, required this.feedback});

  final bool correct;
  final String feedback;
}

class Schemas {
  const Schemas._();

  static String _text(Object? value) => value == null ? '' : '$value';

  // ------------------------------------------------------------ suggestions

  static final suggestions = AiSchema<List<FocusSuggestion>>(
    name: 'foreslaa_fokus',
    description: 'Aflevér 3-5 forslag til hvad brugeren kan fokusere på nu.',
    schema: const {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'suggestions': {
          'type': 'array',
          'minItems': 0,
          'maxItems': 5,
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'title': {'type': 'string', 'description': 'Én kort linje.'},
              'reason': {'type': 'string', 'description': 'Én sætning med grunden.'},
              'action': {
                'type': 'string',
                'enum': ['none', 'start_focus', 'make_quiz', 'open_subject', 'open_chat'],
              },
              'subject': {'type': 'string'},
              'topic': {'type': 'string'},
            },
            'required': ['title', 'reason', 'action'],
          },
        },
      },
      'required': ['suggestions'],
    },
    parse: (json) {
      final raw = json['suggestions'] as List? ?? const [];
      return [
        for (final item in raw)
          if (item is Map<String, dynamic> && _text(item['title']).trim().isNotEmpty)
            FocusSuggestion(
              title: _text(item['title']).trim(),
              reason: _text(item['reason']).trim(),
              action: SuggestionActionCodec.parse(item['action'] as String?),
              subjectName: _nullIfBlank(item['subject']),
              topicName: _nullIfBlank(item['topic']),
            ),
      ];
    },
  );

  // ------------------------------------------------------------------ quiz

  static final quiz = AiSchema<List<QuizQuestion>>(
    name: 'lav_quiz',
    description: 'Aflevér quizspørgsmålene.',
    schema: const {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'questions': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 20,
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'kind': {
                'type': 'string',
                'enum': ['multiple_choice', 'true_false', 'short_answer', 'explain'],
              },
              'prompt': {'type': 'string'},
              'options': {
                'type': 'array',
                'items': {'type': 'string'},
                'description':
                    'Fire muligheder ved multiple choice. Tom ved andre typer.',
              },
              'answer': {
                'type': 'string',
                'description':
                    'Det rigtige svar. Ved multiple choice ordret som en af mulighederne.',
              },
              'explanation': {'type': 'string'},
            },
            'required': ['kind', 'prompt', 'answer', 'explanation'],
          },
        },
      },
      'required': ['questions'],
    },
    parse: (json) {
      final raw = json['questions'] as List? ?? const [];
      final questions = <QuizQuestion>[];

      for (final item in raw) {
        if (item is! Map<String, dynamic>) continue;

        final prompt = _text(item['prompt']).trim();
        final answer = _text(item['answer']).trim();
        if (prompt.isEmpty || answer.isEmpty) continue;

        final kind = QuestionKindCodec.parse(item['kind'] as String?);
        var options = [
          for (final o in (item['options'] as List? ?? const []))
            if (_text(o).trim().isNotEmpty) _text(o).trim(),
        ];

        if (kind == QuestionKind.multipleChoice) {
          // A multiple choice question whose answer is not among the options is
          // unanswerable. Repair it rather than storing a trap.
          if (options.length < 2) continue;
          if (!options.contains(answer)) options = [answer, ...options.take(3)];
        } else if (kind == QuestionKind.trueFalse) {
          options = const ['Sandt', 'Falsk'];
        } else {
          options = const [];
        }

        questions.add(QuizQuestion(
          id: 0,
          quizId: 0,
          kind: kind,
          prompt: prompt,
          options: options,
          answer: answer,
          explanation: _nullIfBlank(item['explanation']),
          position: questions.length,
        ));
      }

      if (questions.isEmpty) {
        throw const FormatException('Modellen returnerede ingen brugbare spørgsmål.');
      }
      return questions;
    },
  );

  // ----------------------------------------------------------------- notes

  static final note = AiSchema<StructuredNote>(
    name: 'strukturer_note',
    description: 'Aflevér den strukturerede note.',
    schema: const {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'title': {'type': 'string', 'description': 'Kort, beskrivende titel.'},
        'body': {'type': 'string', 'description': 'Noten som markdown.'},
        'subject': {'type': 'string', 'description': 'Fagnavn, hvis det fremgår.'},
      },
      'required': ['title', 'body'],
    },
    parse: (json) {
      final title = _text(json['title']).trim();
      final body = _text(json['body']).trim();
      if (title.isEmpty || body.isEmpty) {
        throw const FormatException('Noten kom tilbage tom.');
      }
      return StructuredNote(
        title: title,
        bodyMd: body,
        subjectName: _nullIfBlank(json['subject']),
      );
    },
  );

  // ---------------------------------------------------------------- memory

  static final memories = AiSchema<List<MemoryCandidate>>(
    name: 'gem_hukommelse',
    description: 'Aflevér det, der er værd at huske. En tom liste er et gyldigt svar.',
    schema: const {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'memories': {
          'type': 'array',
          'maxItems': 6,
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'kind': {
                'type': 'string',
                'enum': ['fact', 'learning', 'preference', 'struggle', 'strength'],
              },
              'key': {'type': 'string', 'description': 'Stabil engelsk slug.'},
              'value': {'type': 'string', 'description': 'Én sætning på dansk.'},
              'confidence': {'type': 'number', 'minimum': 0, 'maximum': 1},
              'subject': {'type': 'string'},
            },
            'required': ['kind', 'key', 'value', 'confidence'],
          },
        },
      },
      'required': ['memories'],
    },
    parse: (json) {
      final raw = json['memories'] as List? ?? const [];
      return [
        for (final item in raw)
          if (item is Map<String, dynamic> &&
              _text(item['key']).trim().isNotEmpty &&
              _text(item['value']).trim().isNotEmpty)
            MemoryCandidate(
              kind: MemoryKindCodec.parse(item['kind'] as String?),
              key: _text(item['key']).trim(),
              value: _text(item['value']).trim(),
              confidence: ((item['confidence'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0),
              subjectName: _nullIfBlank(item['subject']),
            ),
      ];
    },
  );

  // --------------------------------------------------------------- grading

  static final grading = AiSchema<GradedAnswer>(
    name: 'ret_svar',
    description: 'Aflevér bedømmelsen af elevens svar.',
    schema: const {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'correct': {'type': 'boolean'},
        'feedback': {
          'type': 'string',
          'description': 'Én til to sætninger til eleven.',
        },
      },
      'required': ['correct', 'feedback'],
    },
    parse: (json) => GradedAnswer(
      correct: json['correct'] == true,
      feedback: _text(json['feedback']).trim(),
    ),
  );

  static String? _nullIfBlank(Object? value) {
    final text = _text(value).trim();
    return text.isEmpty ? null : text;
  }
}
