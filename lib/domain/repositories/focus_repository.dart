import '../models/focus.dart';

abstract class FocusRepository {
  /// The session left running if the app was closed mid-session, so it can be
  /// resumed or closed off rather than silently lost.
  Future<FocusSession?> openSession();

  Future<FocusSession> start({
    int? subjectId,
    int? topicId,
    int? assignmentId,
    int plannedMinutes = 25,
  });

  Future<FocusSession> finish(int id, {required int actualSeconds, required bool completed});

  Future<List<FocusSession>> recent({int limit = 20});
  Future<FocusSession?> session(int id);

  /// Total focused minutes in a window, for the dashboard and subject pages.
  Future<int> minutesSince(DateTime since, {int? subjectId});
}
