/// Quizzes: what was asked, what was answered, and what that says about the
/// user. The last part is the point — a quiz that does not feed the memory
/// system is just a worksheet.
library;

import 'package:meta/meta.dart';

enum QuestionKind { multipleChoice, trueFalse, shortAnswer, explain }

extension QuestionKindCodec on QuestionKind {
  String get code => switch (this) {
        QuestionKind.multipleChoice => 'multiple_choice',
        QuestionKind.trueFalse => 'true_false',
        QuestionKind.shortAnswer => 'short_answer',
        QuestionKind.explain => 'explain',
      };

  String get label => switch (this) {
        QuestionKind.multipleChoice => 'Multiple choice',
        QuestionKind.trueFalse => 'Sand eller falsk',
        QuestionKind.shortAnswer => 'Skriv svaret',
        QuestionKind.explain => 'Forklar begrebet',
      };

  /// Free-text kinds cannot be graded by string comparison; they need the model.
  bool get needsAiGrading => this == QuestionKind.shortAnswer || this == QuestionKind.explain;

  static QuestionKind parse(String? code) => switch (code) {
        'true_false' => QuestionKind.trueFalse,
        'short_answer' => QuestionKind.shortAnswer,
        'explain' => QuestionKind.explain,
        _ => QuestionKind.multipleChoice,
      };
}

@immutable
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.quizId,
    required this.kind,
    required this.prompt,
    this.options = const [],
    required this.answer,
    this.explanation,
    this.position = 0,
  });

  final int id;
  final int quizId;
  final QuestionKind kind;
  final String prompt;

  /// Choices for multiple choice; empty otherwise.
  final List<String> options;

  /// The correct answer. For multiple choice this is the option text itself,
  /// not an index — indices break the moment options are reordered.
  final String answer;

  final String? explanation;
  final int position;
}

@immutable
class Quiz {
  const Quiz({
    required this.id,
    this.subjectId,
    this.topicId,
    required this.title,
    this.sourceKind = 'topic',
    this.sourceRef,
    required this.createdAt,
    this.questions = const [],
  });

  final int id;
  final int? subjectId;
  final int? topicId;
  final String title;

  /// Where the questions came from: 'topic', 'note', 'mistakes', 'subject'.
  final String sourceKind;
  final String? sourceRef;

  final DateTime createdAt;
  final List<QuizQuestion> questions;

  String get sourceLabel => switch (sourceKind) {
        'note' => 'Lavet ud fra dine noter',
        'mistakes' => 'Lavet ud fra dine tidligere fejl',
        'subject' => 'Lavet ud fra faget',
        _ => 'Lavet ud fra emnet',
      };
}

@immutable
class QuizAnswer {
  const QuizAnswer({
    required this.questionId,
    required this.given,
    required this.correct,
    this.aiFeedback,
  });

  final int questionId;
  final String given;
  final bool correct;

  /// Why it was wrong, in the user's own terms. Written after grading.
  final String? aiFeedback;
}

@immutable
class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.quizId,
    required this.startedAt,
    this.finishedAt,
    this.score = 0,
    this.total = 0,
    this.answers = const [],
  });

  final int id;
  final int quizId;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int score;
  final int total;
  final List<QuizAnswer> answers;

  bool get isFinished => finishedAt != null;
  double get ratio => total == 0 ? 0 : score / total;
  int get percent => (ratio * 100).round();

  /// "Du scorede 8/10"
  String get scoreLine => '$score/$total';
}
