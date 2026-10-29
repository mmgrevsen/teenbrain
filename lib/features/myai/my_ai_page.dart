/// What the app knows about the user — visible, editable, deletable.
///
/// Every claim on this page shows where it came from. If TeenBrain cannot say
/// why it believes something, it has no business believing it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/models/memory.dart';
import '../../domain/models/school.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class MyAiPage extends ConsumerWidget {
  const MyAiPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(memoriesProvider);
    final settings = ref.watch(settingsProvider);
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final text = Theme.of(context).textTheme;

    return PageBody(
      children: [
        const PageTitle(
          'Min AI',
          subtitle: 'Alt jeg har lært om dig. Du bestemmer hvad der bliver.',
        ),

        if (!settings.aiMemoryEnabled)
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Hukommelsen er slået fra. Det her er stadig gemt, men jeg bruger '
                    'ikke noget af det, før du slår den til igen.',
                    style: text.bodyMedium,
                  ),
                ),
                const SizedBox(width: 14),
                AppButton(
                  label: 'Slå til',
                  onPressed: () => ref.read(settingsProvider.notifier).setAiMemory(true),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),
        const _ContextPreview(),
        const SizedBox(height: 28),

        async.when(
          loading: () => const Column(
            children: [
              SkeletonBox(height: 80, radius: Insets.radius),
              SizedBox(height: 10),
              SkeletonBox(height: 80, radius: Insets.radius),
            ],
          ),
          error: (error, _) => InlineError(message: 'Kunne ikke hente hukommelsen: $error'),
          data: (memories) {
            if (memories.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 30),
                child: EmptyState(
                  icon: AppIcons.myAi,
                  title: 'Jeg ved ikke noget om dig endnu',
                  message:
                      'Efterhånden som du skriver, tager quizzer og arbejder, '
                      'begynder jeg at lægge mærke til mønstre. Alt jeg finder ud af, '
                      'kommer til at stå her.',
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final kind in MemoryKind.values)
                  _Group(
                    kind: kind,
                    memories: memories.where((m) => m.kind == kind).toList(),
                    subjects: subjects,
                  ),
                const SizedBox(height: 24),
                _DangerZone(count: memories.length),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Shows exactly what would be sent with the next question.
///
/// The claim "we don't send your whole database" is worth nothing unless the
/// user can look.
class _ContextPreview extends ConsumerStatefulWidget {
  const _ContextPreview();

  @override
  ConsumerState<_ContextPreview> createState() => _ContextPreviewState();
}

class _ContextPreviewState extends ConsumerState<_ContextPreview> {
  MemoryContext? _context;
  bool _open = false;
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final context = await ref.read(brainProvider).buildContext(query: 'hvad ved du om mig');
    if (!mounted) return;
    setState(() {
      _context = context;
      _loading = false;
      _open = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final built = _context;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hvad jeg sender med', style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Jeg sender aldrig hele din database — kun det, der er relevant '
                      'for lige det spørgsmål, inden for et fast budget.',
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              AppButton(
                label: _open ? 'Skjul' : (_loading ? 'Henter …' : 'Vis mig'),
                onPressed: _loading
                    ? null
                    : _open
                        ? () => setState(() => _open = false)
                        : _load,
              ),
            ],
          ),
          if (_open && built != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Tag('${built.estimatedTokens} tokens', filled: true,
                    tone: context.colors.accent),
                const SizedBox(width: 8),
                Tag('${built.memories.length} af ${built.consideredCount} vurderet'),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.surfaceHover,
                borderRadius: BorderRadius.circular(Insets.radiusSmall),
              ),
              child: SelectableText(
                built.rendered.isEmpty
                    ? 'Der er ingenting at sende med endnu.'
                    : built.rendered,
                style: text.bodySmall!.copyWith(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['Menlo', 'Consolas'],
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.kind, required this.memories, required this.subjects});

  final MemoryKind kind;
  final List<Memory> memories;
  final List<Subject> subjects;

  @override
  Widget build(BuildContext context) {
    if (memories.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(kind.sectionTitle),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final memory in memories)
                  _MemoryRow(memory: memory, subjects: subjects),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryRow extends ConsumerWidget {
  const _MemoryRow({required this.memory, required this.subjects});

  final Memory memory;
  final List<Subject> subjects;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final subject = subjects.where((s) => s.id == memory.subjectId).firstOrNull;

    return Opacity(
      opacity: memory.active ? 1 : 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memory.value,
                    style: text.bodyLarge!.copyWith(
                      decoration: memory.active ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(memory.source.label, style: text.labelSmall),
                      if (subject != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SubjectDot(token: subject.colorToken, size: 6),
                            const SizedBox(width: 5),
                            Text(subject.name, style: text.labelSmall),
                          ],
                        ),
                      Text(shortAgo(memory.updatedAt), style: text.labelSmall),
                      if (memory.useCount > 0)
                        Text('brugt ${memory.useCount}×', style: text.labelSmall),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _RowMenu(memory: memory),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () async {
                await ref.read(memoryStoreProvider).setActive(memory.id, !memory.active);
                ref.read(dataRevisionProvider.notifier).bump();
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Tooltip(
                  message: memory.active ? 'Slå fra' : 'Slå til',
                  child: AppSwitch(value: memory.active, tone: colors.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowMenu extends ConsumerWidget {
  const _RowMenu({required this.memory});
  final Memory memory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return PopupMenuButton<String>(
      color: colors.surface,
      tooltip: 'Mere',
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'edit', child: Text('Redigér')),
        PopupMenuItem(
          value: 'pin',
          child: Text(memory.pinned ? 'Fjern fastgørelse' : 'Fastgør'),
        ),
        const PopupMenuItem(value: 'source', child: Text('Hvor kommer den fra?')),
        PopupMenuItem(
          value: 'delete',
          child: Text('Slet', style: TextStyle(color: colors.danger)),
        ),
      ],
      onSelected: (value) async {
        final store = ref.read(memoryStoreProvider);
        switch (value) {
          case 'edit':
            await _edit(context, ref);
          case 'pin':
            await store.setPinned(memory.id, !memory.pinned);
            ref.read(dataRevisionProvider.notifier).bump();
          case 'source':
            await _showSource(context, ref);
          case 'delete':
            await store.delete(memory.id);
            ref.read(dataRevisionProvider.notifier).bump();
        }
      },
      child: Icon(AppIcons.more, size: 18, color: colors.textTertiary),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: memory.value);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: const Text('Ret hvad jeg husker'),
        content: AppTextField(
          controller: controller,
          minLines: 2,
          maxLines: 5,
          autofocus: true,
          padding: const EdgeInsets.all(12),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annullér')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Gem')),
        ],
      ),
    );
    final value = controller.text.trim();
    controller.dispose();

    if (saved != true || value.isEmpty) return;
    await ref.read(memoryStoreProvider).edit(memory.id, value);
    ref.read(dataRevisionProvider.notifier).bump();
  }

  Future<void> _showSource(BuildContext context, WidgetRef ref) async {
    final links = await ref.read(memoryStoreProvider).linksFor(memory.id);
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.surface,
        title: const Text('Hvor kommer den fra?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(memory.source.label,
                style: Theme.of(dialogContext).textTheme.bodyLarge),
            const SizedBox(height: 10),
            Text(
              'Nøgle: ${memory.key}\n'
              'Sikkerhed: ${(memory.confidence * 100).round()} %\n'
              'Oprettet: ${dayHeading(memory.createdAt)}',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            if (links.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Bygget på:', style: Theme.of(dialogContext).textTheme.labelSmall),
              for (final link in links)
                Text(
                  '· ${_describe(link)}',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Luk'),
          ),
        ],
      ),
    );
  }

  String _describe(MemoryLink link) => switch (link.refTable) {
        'quizzes' => 'en quiz',
        'conversations' => 'en samtale',
        'notes' => 'en note',
        _ => link.refTable,
      };
}

class _DangerZone extends ConsumerWidget {
  const _DangerZone({required this.count});
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Glem alt om mig', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Sletter alle $count ting jeg har lært. Dine noter, quizzer og '
                  'timeline rører jeg ikke.',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          AppButton(
            label: 'Slet hukommelse',
            tone: ButtonTone.danger,
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: context.colors.surface,
                  title: const Text('Slette alt jeg har lært?'),
                  content: const Text(
                    'Jeg starter forfra med at lære dig at kende. '
                    'Det kan ikke fortrydes.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Behold'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('Slet alt',
                          style: TextStyle(color: context.colors.danger)),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await ref.read(memoryStoreProvider).deleteAll();
              ref.read(dataRevisionProvider.notifier).bump();
            },
          ),
        ],
      ),
    );
  }
}
