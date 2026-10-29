import '../models/quiz.dart';

abstract class QuizRepository {
  Future<List<Quiz>> quizzes({int? subjectId, int limit = 100});

  /// The quiz with its questions loaded.
  Future<Quiz?> quiz(int id);

  Future<Quiz> create({
    required String title,
    int? subjectId,
    int? topicId,
    String sourceKind = 'topic',
    String? sourceRef,
    required List<QuizQuestion> questions,
  });

  Future<void> deleteQuiz(int id);

  Future<QuizAttempt> startAttempt(int quizId);

  Future<void> recordAnswer({
    required int attemptId,
    required int questionId,
    required String given,
    required bool correct,
    String? aiFeedback,
  });

  Future<QuizAttempt> finishAttempt(int attemptId);
  Future<QuizAttempt?> attempt(int id);
  Future<List<QuizAttempt>> attemptsFor(int quizId);

  /// Questions the user has got wrong, newest first. This is what "lav en quiz
  /// ud fra mine tidligere fejl" reads, and what the memory system mines for
  /// struggle memories.
  Future<List<QuizQuestion>> recentMistakes({int? subjectId, int limit = 20});

  /// Answered/correct totals for a subject, for the Subjects page.
  Future<({int answered, int correct})> accuracyFor(int subjectId, {DateTime? since});
}
