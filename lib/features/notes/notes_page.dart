import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/models/note.dart';
import '../../domain/models/school.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key, this.subjectId});
  final int? subjectId;

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  late int? _subjectId = widget.subjectId;

  Future<void> _create() async {
    final note = await ref.read(noteRepositoryProvider).create(
          title: 'Ny note',
          subjectId: _subjectId,
        );
    ref.read(dataRevisionProvider.notifier).bump();
    if (!mounted) return;
    ref.read(navigationProvider.notifier).push(NoteDetailRoute(note.id));
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider(_subjectId)).value;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final nav = ref.read(navigationProvider.notifier);

    return PageBody(
      children: [
        PageTitle(
          'Noter',
          subtitle: 'Alt du har skrevet, og alt AI\'en har struktureret for dig.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: 'Live Notes',
                onPressed: () => nav.push(const LiveNotesRoute()),
              ),
              AppButton(label: 'Ny note', tone: ButtonTone.primary, onPressed: _create),
            ],
          ),
        ),
        if (subjects.isNotEmpty) ...[
          ChoiceRow<int?>(
            selected: _subjectId,
            onSelected: (value) => setState(() => _subjectId = value),
            options: [
              (value: null, label: 'Alle'),
              for (final subject in subjects) (value: subject.id, label: subject.name),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (notes == null)
          const Column(
            children: [
              SkeletonBox(height: 74, radius: Insets.radius),
              SizedBox(height: 8),
              SkeletonBox(height: 74, radius: Insets.radius),
            ],
          )
        else if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyState(
              icon: AppIcons.notes,
              title: 'Ingen noter endnu',
              message: _subjectId == null
                  ? 'Skriv en note, eller lad AI\'en strukturere noget tekst for dig.'
                  : 'Der er ingen noter i det fag endnu.',
              action: AppButton(
                label: 'Skriv den første',
                tone: ButtonTone.primary,
                onPressed: _create,
              ),
            ),
          )
        else
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _NoteCard(note: note, subjects: subjects),
            ),
      ],
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note, required this.subjects});

  final Note note;
  final List<Subject> subjects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final subject = subjects.where((s) => s.id == note.subjectId).firstOrNull;

    return Panel(
      onTap: () => ref.read(navigationProvider.notifier).push(NoteDetailRoute(note.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (note.pinned) ...[
                Icon(AppIcons.pinned, size: 13, color: colors.accent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(note.title, style: text.titleMedium, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 12),
              Text(shortAgo(note.updatedAt), style: text.bodySmall),
            ],
          ),
          if (note.preview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (subject != null) ...[
                SubjectDot(token: subject.colorToken),
                const SizedBox(width: 6),
                Text(subject.name, style: text.labelSmall),
                const SizedBox(width: 12),
              ],
              if (note.source != NoteSource.manual)
                Tag(note.source.label, tone: colors.accent),
              const Spacer(),
              if (note.wordCount > 0)
                Text('${note.wordCount} ord', style: text.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}
