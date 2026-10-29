/// Notes. Markdown in, markdown out — the editor is plain text and the reader
/// renders it, so nothing about a note is locked inside a widget tree.
library;

import 'package:meta/meta.dart';

enum NoteSource { manual, ai, liveNotes, imported }

extension NoteSourceCodec on NoteSource {
  String get code => switch (this) {
        NoteSource.manual => 'manual',
        NoteSource.ai => 'ai',
        NoteSource.liveNotes => 'live_notes',
        NoteSource.imported => 'import',
      };

  String get label => switch (this) {
        NoteSource.manual => 'Skrevet af dig',
        NoteSource.ai => 'Lavet af AI',
        NoteSource.liveNotes => 'Live Notes',
        NoteSource.imported => 'Importeret',
      };

  static NoteSource parse(String? code) => switch (code) {
        'ai' => NoteSource.ai,
        'live_notes' => NoteSource.liveNotes,
        'import' => NoteSource.imported,
        _ => NoteSource.manual,
      };
}

@immutable
class Note {
  const Note({
    required this.id,
    this.subjectId,
    this.topicId,
    required this.title,
    this.bodyMd = '',
    this.source = NoteSource.manual,
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int? subjectId;
  final int? topicId;
  final String title;
  final String bodyMd;
  final NoteSource source;
  final bool pinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// First non-heading line, for list previews.
  String get preview {
    for (final line in bodyMd.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      return t.replaceAll(RegExp(r'^[-*]\s*'), '');
    }
    return '';
  }

  int get wordCount => bodyMd.trim().isEmpty ? 0 : bodyMd.trim().split(RegExp(r'\s+')).length;

  Note copyWith({
    int? subjectId,
    bool clearSubject = false,
    int? topicId,
    bool clearTopic = false,
    String? title,
    String? bodyMd,
    bool? pinned,
    DateTime? updatedAt,
  }) =>
      Note(
        id: id,
        subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
        topicId: clearTopic ? null : (topicId ?? this.topicId),
        title: title ?? this.title,
        bodyMd: bodyMd ?? this.bodyMd,
        source: source,
        pinned: pinned ?? this.pinned,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
