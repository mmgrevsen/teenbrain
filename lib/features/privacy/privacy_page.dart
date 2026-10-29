/// Privacy.
///
/// One page listing every way the app can observe the user, what is stored,
/// where it lives, and what leaves the machine. Everything that observes is off
/// until switched on here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/app_paths.dart';
import '../../domain/models/memory.dart';
import '../../domain/models/note.dart';
import '../../domain/models/timeline.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final onDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    // Transcription is macOS-only in this build, and the switch says so rather
    // than letting the user arm something that cannot fire.
    final micSupported = ref.watch(transcriptionStackProvider).isSupported;

    return PageBody(
      children: [
        const PageTitle(
          'Privatliv',
          subtitle: 'Hvad appen må, og hvad der bliver gemt. Du bestemmer det hele.',
        ),

        const _WhatLeaves(),
        const SizedBox(height: 28),

        const SectionHeading('Hvad appen må'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              SettingSwitch(
                title: 'AI-hukommelse',
                description: settings.aiMemoryEnabled
                    ? 'Jeg husker ting om dig og bruger dem i mine svar. '
                        'Du kan se og slette alt under Min AI.'
                    : 'Jeg husker ingenting mellem samtaler.',
                value: settings.aiMemoryEnabled,
                onChanged: controller.setAiMemory,
              ),
              SettingSwitch(
                title: 'Skærmforståelse',
                description: 'Lader appen se hvad du arbejder med, og tilbyde hjælp. '
                    'Der vises altid en rød indikator, mens den er aktiv.',
                value: settings.screenUnderstandingEnabled,
                enabled: onDesktop,
                disabledNote: 'Kun på computer. Findes ikke på telefonen.',
                tone: colors.recording,
                onChanged: (value) async {
                  if (!value) {
                    controller.setScreenUnderstanding(false);
                    return;
                  }
                  // Turning this on is a real decision, so it gets a real page.
                  ref.read(navigationProvider.notifier).push(
                        const ScreenUnderstandingRoute(),
                      );
                },
              ),
              SettingSwitch(
                title: 'Mikrofon',
                description: settings.microphoneEnabled
                    ? 'Live Notes må optage, når du selv starter den. '
                        'Talegenkendelsen kører lokalt, og lyden gemmes aldrig.'
                    : 'Til Live Notes. Appen beder først macOS om adgang, '
                        'den dag du trykker optag.',
                value: settings.microphoneEnabled,
                enabled: micSupported,
                disabledNote:
                    'Optagelse findes kun på macOS. Du kan stadig indsætte tekst '
                    'i Live Notes og få den struktureret.',
                tone: colors.recording,
                onChanged: controller.setMicrophone,
              ),
              SettingSwitch(
                title: 'Kamera',
                description: 'Bruges ikke af TeenBrain.',
                value: false,
                enabled: false,
                disabledNote: 'TeenBrain bruger ikke kameraet til noget.',
                onChanged: null,
              ),
              SettingSwitch(
                title: 'Automatiske noter',
                description:
                    'Lav noter af en optagelse uden at spørge, når du stopper den.',
                value: settings.automaticNotesEnabled,
                enabled: false,
                disabledNote:
                    'Ikke bygget. Lige nu lander en optagelse altid i editoren, '
                    'så du kan rette fagord, før den bliver til en note — og det '
                    'er ærligt talt den rigtige rækkefølge indtil videre.',
                onChanged: null,
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),
        const SectionHeading('Opbevaring'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hvor længe skal aktiviteter gemmes?', style: text.titleMedium),
              const SizedBox(height: 12),
              ChoiceRow<int>(
                selected: settings.retentionDays,
                onSelected: controller.setRetentionDays,
                options: const [
                  (value: 0, label: 'For altid'),
                  (value: 365, label: '1 år'),
                  (value: 180, label: '6 måneder'),
                  (value: 90, label: '3 måneder'),
                  (value: 30, label: '30 dage'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                settings.retentionDays == 0
                    ? 'Intet bliver slettet automatisk.'
                    : 'Aktiviteter ældre end ${settings.retentionDays} dage ryddes op '
                        'ved næste opstart. Noter og fag bliver.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),
        const _StoredData(),
        const SizedBox(height: 28),
        const _DeleteEverything(),
      ],
    );
  }
}

/// The one thing a privacy page usually leaves vague, said plainly.
class _WhatLeaves extends ConsumerWidget {
  const _WhatLeaves();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final configured = ref.watch(aiStackProvider).isConfigured;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hvad forlader din computer', style: text.titleMedium),
          const SizedBox(height: 12),
          if (configured) ...[
            _Line(
              tone: colors.warning,
              label: 'Sendes til Anthropic',
              body: 'Det du skriver i chatten, og de relevante stumper hukommelse '
                  'og noter, jeg vælger at sende med. Du kan se præcis hvad, '
                  'under Min AI ▸ Hvad jeg sender med.',
            ),
            const SizedBox(height: 10),
          ],
          _Line(
            tone: colors.positive,
            label: 'Bliver her',
            body: 'Alt andet. Noter, quizzer, resultater, timeline, hukommelse og '
                'indstillinger ligger i én fil på din egen maskine. '
                '${configured ? 'De sendes kun, hvis de udvælges som kontekst til et spørgsmål.' : 'Uden en API-nøgle forlader ingenting maskinen overhovedet.'}',
          ),
          const SizedBox(height: 10),
          _Line(
            tone: colors.positive,
            label: 'Sendes aldrig',
            body: 'Lyd. Live Notes genkender tale lokalt på din Mac og nægter at '
                'starte, hvis den ikke kan — den falder aldrig tilbage på en '
                'server. Lyden gemmes heller ikke: der er kun tekst undervejs. '
                'Derudover er der ingen analytics, ingen crash-rapportering og '
                'ingen konto.',
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.tone, required this.label, required this.body});

  final Color tone;
  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 10),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.labelMedium!.copyWith(color: tone)),
              const SizedBox(height: 2),
              Text(body, style: text.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _StoredData extends ConsumerWidget {
  const _StoredData();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final notes = ref.watch(notesProvider(null)).value?.length ?? 0;
    final quizzes = ref.watch(quizzesProvider).value?.length ?? 0;
    final memories = ref.watch(memoriesProvider).value?.length ?? 0;
    final conversations = ref.watch(conversationsProvider).value?.length ?? 0;
    final path = AppPaths.dataDirectory().path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeading('Det der ligger gemt'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 22,
                runSpacing: 12,
                children: [
                  _Count(label: 'Noter', value: notes),
                  _Count(label: 'Samtaler', value: conversations),
                  _Count(label: 'Quizzer', value: quizzes),
                  _Count(label: 'Hukommelse', value: memories),
                ],
              ),
              const SizedBox(height: 18),
              Text('Alt ligger her:', style: text.labelSmall),
              const SizedBox(height: 4),
              SelectableText(path, style: text.bodySmall),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AppButton(
                    label: 'Eksportér som JSON',
                    onPressed: () => _export(context, ref),
                  ),
                  AppButton(
                    label: 'Kopiér sti',
                    onPressed: () => copyToClipboard(context, path, label: 'Sti kopieret'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final profile = await ref.read(profileRepositoryProvider).read();
      final payload = {
        'exported_at': DateTime.now().toIso8601String(),
        'profile': profile == null
            ? null
            : {
                'name': profile.displayName,
                'grade_level': profile.gradeLevel,
                'xp': profile.xp,
              },
        'subjects': [
          for (final s in await ref.read(schoolRepositoryProvider).subjects())
            {'name': s.name, 'created_at': s.createdAt.toIso8601String()},
        ],
        'notes': [
          for (final n in await ref.read(noteRepositoryProvider).notes(limit: 10000))
            {
              'title': n.title,
              'body': n.bodyMd,
              'source': n.source.code,
              'updated_at': n.updatedAt.toIso8601String(),
            },
        ],
        'memories': [
          for (final m in await ref.read(memoryStoreProvider).all())
            {
              'kind': m.kind.code,
              'key': m.key,
              'value': m.value,
              'source': m.source.code,
              'active': m.active,
            },
        ],
        'timeline': [
          for (final e in await ref.read(timelineRepositoryProvider).events(limit: 10000))
            {
              'kind': e.kind.code,
              'title': e.title,
              'summary': e.summary,
              'started_at': e.startedAt.toIso8601String(),
            },
        ],
      };

      final file = File(
        '${AppPaths.exportDirectory().path}/teenbrain-eksport-'
        '${DateTime.now().toIso8601String().split('T').first}.json',
      );
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));

      messenger.showSnackBar(
        SnackBar(
          content: Text('Gemt: ${file.path}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Eksporten fejlede: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: text.headlineSmall),
        Text(label, style: text.labelSmall),
      ],
    );
  }
}

class _DeleteEverything extends ConsumerWidget {
  const _DeleteEverything();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Slet alle data', style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Fjerner alt: profil, fag, noter, samtaler, quizzer, timeline og '
            'hukommelse. Appen starter forfra, som var den lige installeret. '
            'Din API-nøgle bliver også slettet.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 14),
          AppButton(
            label: 'Slet alt',
            tone: ButtonTone.danger,
            onPressed: () => _confirm(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.surface,
        title: const Text('Slette alt?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Det kan ikke fortrydes. Skriv SLET for at bekræfte.',
            ),
            const SizedBox(height: 14),
            AppTextField(controller: controller, hint: 'SLET', autofocus: true),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Fortryd'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim().toUpperCase() == 'SLET',
            ),
            child: Text('Slet alt', style: TextStyle(color: dialogContext.colors.danger)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true) return;

    final database = ref.read(bootstrapProvider).requireValue.database.db;
    for (final table in const [
      'memory_links', 'memories', 'quiz_answers', 'quiz_attempts', 'quiz_questions',
      'quizzes', 'messages', 'conversations', 'notes', 'focus_sessions',
      'timeline_events', 'assignments', 'topics', 'subjects', 'daily_activity',
      'achievements', 'search_map', 'profile',
    ]) {
      database.execute('DELETE FROM $table');
    }
    await ref.read(searchIndexProvider).rebuild();
    await ref.read(apiKeyProvider.notifier).clear();

    ref.read(dataRevisionProvider.notifier).bump();
    ref.invalidate(profileProvider);

    if (!context.mounted) return;
    ref.read(navigationProvider.notifier).go(const HomeRoute());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Alt er slettet.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
