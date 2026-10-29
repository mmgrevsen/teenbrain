import '../models/timeline.dart';

/// Every feature writes here. The Timeline page, the dashboard's "what have I
/// been doing" and half of search all read from this one spine.
abstract class TimelineRepository {
  Future<TimelineEvent> record({
    required TimelineKind kind,
    required String title,
    String? summary,
    int? subjectId,
    String? refTable,
    int? refId,
    DateTime? startedAt,
    DateTime? endedAt,
  });

  Future<List<TimelineEvent>> events({
    DateTime? after,
    DateTime? before,
    int? subjectId,
    Set<TimelineKind>? kinds,
    int limit = 200,
  });

  /// Grouped by calendar day, newest day first.
  Future<List<TimelineDay>> days({int limit = 30});

  Future<TimelineEvent?> event(int id);
  Future<void> delete(int id);

  /// When the user last touched a subject — "du har ikke repeteret engelsk i
  /// 4 dage" comes from here.
  Future<Map<int, DateTime>> lastTouchedPerSubject();
}
