import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../brain/brain_service.dart';
import '../../core/time_format.dart';
import '../../domain/models/note.dart';
import '../../domain/models/school.dart';
import '../../domain/services/ai_client.dart';
import '../../shared/widgets/markdown_text.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class NoteDetailPage extends ConsumerStatefulWidget {
  const NoteDetailPage({super.key, required this.noteId});
  final int noteId;

  @override
  ConsumerState<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends ConsumerState<NoteDetailPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  Note? _note;
  bool _missing = false;
  Timer? _saveTimer;
  bool _editing = true;
  bool _dirty = false;
  bool _makingQuiz = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // A pending edit must not be lost by navigating away.
    if (_dirty) unawaited(_save());
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final note = await ref.read(noteRepositoryProvider).note(widget.noteId);
    if (!mounted) return;
    if (note == null) {
      // A note reached from a stale link or a deleted search hit. Say so —
      // an endless skeleton is the worst of both worlds.
      setState(() => _missing = true);
      return;
    }
    setState(() {
      _note = note;
      _title.text = note.title;
      _body.text = note.bodyMd;
      // An AI-written note opens as something to read; a note you are writing
      // opens as something to write.
      _editing = note.source == NoteSource.manual;
    });
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _save() async {
    final note = _note;
    if (note == null || !_dirty) return;
    _dirty = false;

    final updated = await ref.read(noteRepositoryProvider).update(
          note.copyWith(
            title: _title.text.trim().isEmpty ? 'Uden titel' : _title.text.trim(),
            bodyMd: _body.text,
            updatedAt: DateTime.now(),
          ),
        );
    if (!mounted) return;
    setState(() => _note = updated);
    ref.read(dataRevisionProvider.notifier).bump();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: const Text('Slet noten?'),
        content: const Text('Den kan ikke hentes tilbage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Behold'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Slet', style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _dirty = false;
    await ref.read(noteRepositoryProvider).delete(widget.noteId);
    ref.read(dataRevisionProvider.notifier).bump();
    if (!mounted) return;
    ref.read(navigationProvider.notifier).pop();
  }

  Future<void> _makeQuiz() async {
    final note = _note;
    if (note == null) return;

    setState(() {
      _makingQuiz = true;
      _error = null;
    });

    try {
      await _save();
      final quiz = await ref.read(brainProvider).generateQuiz(
            title: 'Quiz: ${note.title}',
            subjectId: note.subjectId,
            topicId: note.topicId,
            source: QuizSource.notes,
          );
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) return;
      ref.read(navigationProvider.notifier).push(QuizRunRoute(quiz.id));
    } on AiFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Kunne ikke lave quizzen: $e');
    } finally {
      if (mounted) setState(() => _makingQuiz = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = _note;
    final text = Theme.of(context).textTheme;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];

    if (_missing) {
      return PageBody(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyState(
              icon: AppIcons.notes,
              title: 'Noten findes ikke',
              message: 'Den er slettet, eller linket peger på noget der er væk.',
              action: AppButton(
                label: 'Til noterne',
                tone: ButtonTone.primary,
                onPressed: () => ref.read(navigationProvider.notifier).go(const NotesRoute()),
              ),
            ),
          ),
        ],
      );
    }

    if (note == null) {
      return const PageBody(
        children: [
          SkeletonBox(height: 32, width: 240),
          SizedBox(height: 20),
          SkeletonBox(height: 200, radius: Insets.radius),
        ],
      );
    }

    return PageBody(
      children: [
        TextField(
          controller: _title,
          onChanged: (_) => _scheduleSave(),
          style: text.headlineMedium,
          cursorColor: context.colors.accent,
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            hintText: 'Uden titel',
            hintStyle: text.headlineMedium!.copyWith(color: context.colors.textTertiary),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _SubjectPicker(
              subjects: subjects,
              selected: note.subjectId,
              onChanged: (id) async {
                final updated = await ref.read(noteRepositoryProvider).update(
                      note.copyWith(subjectId: id, clearSubject: id == null),
                    );
                ref.read(dataRevisionProvider.notifier).bump();
                if (mounted) setState(() => _note = updated);
              },
            ),
            const SizedBox(width: 12),
            Text('Redigeret ${shortAgo(note.updatedAt)}', style: text.bodySmall),
            const Spacer(),
            if (note.source != NoteSource.manual) Tag(note.source.label),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            ChoiceRow<bool>(
              selected: _editing,
              onSelected: (value) {
                if (!value) unawaited(_save());
                setState(() => _editing = value);
              },
              options: const [(value: true, label: 'Skriv'), (value: false, label: 'Læs')],
            ),
            const Spacer(),
            AppButton(
              label: note.pinned ? 'Fastgjort' : 'Fastgør',
              onPressed: () async {
                await ref.read(noteRepositoryProvider).setPinned(note.id, !note.pinned);
                ref.read(dataRevisionProvider.notifier).bump();
                final refreshed = await ref.read(noteRepositoryProvider).note(note.id);
                if (mounted) setState(() => _note = refreshed);
              },
            ),
            const SizedBox(width: 8),
            AppButton(
              label: _makingQuiz ? 'Laver quiz …' : 'Lav quiz',
              onPressed: _makingQuiz || !ref.watch(aiStackProvider).isConfigured
                  ? null
                  : _makeQuiz,
            ),
            const SizedBox(width: 8),
            AppButton(label: 'Slet', tone: ButtonTone.danger, onPressed: _delete),
          ],
        ),
        if (!ref.watch(aiStackProvider).isConfigured)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Quiz kræver en API-nøgle under Indstillinger.',
              style: text.bodySmall,
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          InlineError(message: _error!, onRetry: _makeQuiz),
        ],
        const SizedBox(height: 18),
        if (_editing)
          AppTextField(
            controller: _body,
            hint: 'Skriv din note her. Markdown virker: ## overskrift, - punkt, **fed**.',
            minLines: 14,
            maxLines: 200,
            onChanged: (_) => _scheduleSave(),
            padding: const EdgeInsets.all(16),
          )
        else
          Panel(
            padding: const EdgeInsets.all(20),
            child: note.bodyMd.trim().isEmpty
                ? Text('Noten er tom.', style: text.bodyMedium)
                : MarkdownText(note.bodyMd),
          ),
      ],
    );
  }
}

class _SubjectPicker extends StatelessWidget {
  const _SubjectPicker({
    required this.subjects,
    required this.selected,
    required this.onChanged,
  });

  final List<Subject> subjects;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = subjects.where((s) => s.id == selected).firstOrNull;

    return PopupMenuButton<int?>(
      onSelected: onChanged,
      color: colors.surface,
      tooltip: 'Vælg fag',
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('Intet fag')),
        for (final subject in subjects)
          PopupMenuItem(
            value: subject.id,
            child: Row(
              children: [
                SubjectDot(token: subject.colorToken),
                const SizedBox(width: 8),
                Text(subject.name),
              ],
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (current != null) ...[
            SubjectDot(token: current.colorToken),
            const SizedBox(width: 6),
          ],
          Text(
            current?.name ?? 'Vælg fag',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Icon(AppIcons.expand, size: 15, color: colors.textTertiary),
        ],
      ),
    );
  }
}
