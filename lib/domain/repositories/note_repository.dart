import '../models/note.dart';

abstract class NoteRepository {
  Future<List<Note>> notes({int? subjectId, int? topicId, int limit = 200});
  Future<Note?> note(int id);
  Future<List<Note>> recent({int limit = 5});

  Future<Note> create({
    required String title,
    String bodyMd,
    int? subjectId,
    int? topicId,
    NoteSource source = NoteSource.manual,
  });

  Future<Note> update(Note note);
  Future<void> setPinned(int id, bool pinned);
  Future<void> delete(int id);

  /// Raw text of the user's notes for a subject, for feeding a quiz generator.
  /// Capped by character count, newest first — a prompt has a budget.
  Future<String> corpusFor({int? subjectId, int? topicId, int maxChars = 12000});
}
