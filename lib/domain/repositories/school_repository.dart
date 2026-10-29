import '../models/school.dart';

/// Subjects, topics and assignments — the structure the user's school year has.
abstract class SchoolRepository {
  Future<List<Subject>> subjects({bool includeArchived = false});
  Future<Subject?> subject(int id);

  /// Looks a subject up by name, case- and diacritic-insensitively. The AI
  /// names subjects rather than knowing their ids, so this is how its tool
  /// calls land on the right row.
  Future<Subject?> subjectByName(String name);

  Future<Subject> createSubject(String name, {String? colorToken});
  Future<Subject> updateSubject(Subject subject);
  Future<void> deleteSubject(int id);
  Future<void> reorderSubjects(List<int> idsInOrder);

  Future<List<Topic>> topics(int subjectId);
  Future<List<Topic>> allTopics();
  Future<Topic?> topic(int id);

  /// Creates the topic if it is new, returns the existing one if not. Topics
  /// appear as a side effect of work, so this is the common path.
  Future<Topic> ensureTopic(int subjectId, String name);

  /// Nudges mastery towards [observed] rather than overwriting it, so a single
  /// bad quiz does not erase a term of work. Returns the updated topic.
  Future<Topic> recordMastery(int topicId, double observed, {double weight = 0.35});

  Future<void> touchTopic(int topicId);
  Future<void> deleteTopic(int id);

  Future<List<Assignment>> assignments({bool includeCompleted = false, int? subjectId});

  /// Open assignments with a due date, soonest first — what the dashboard needs.
  Future<List<Assignment>> upcoming({int limit = 5});

  Future<Assignment?> assignment(int id);
  Future<Assignment> createAssignment({
    int? subjectId,
    required String title,
    String? description,
    DateTime? dueAt,
    int? estimatedMinutes,
  });
  Future<Assignment> updateAssignment(Assignment assignment);
  Future<void> setAssignmentDone(int id, bool done);
  Future<void> deleteAssignment(int id);

  /// Everything the Subjects page shows, assembled in one pass instead of an
  /// N+1 storm of per-subject queries.
  Future<List<SubjectSummary>> summaries();
  Future<SubjectSummary?> summary(int subjectId);
}
