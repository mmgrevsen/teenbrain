import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/api_key_store.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/settings_store.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class AppSettingsPage extends ConsumerWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final profile = ref.watch(profileProvider).value;
    final nav = ref.read(navigationProvider.notifier);

    return PageBody(
      children: [
        const PageTitle('Indstillinger'),

        const SectionHeading('AI'),
        const _ApiKeyCard(),

        const SizedBox(height: 28),
        const SectionHeading('Udseende'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tema', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ChoiceRow<AppThemeMode>(
                selected: settings.themeMode,
                onSelected: controller.setThemeMode,
                options: const [
                  (value: AppThemeMode.system, label: 'Følg systemet'),
                  (value: AppThemeMode.light, label: 'Lyst'),
                  (value: AppThemeMode.dark, label: 'Mørkt'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),
        const SectionHeading('Fremdrift'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SettingSwitch(
            title: 'Streaks, XP og levels',
            description: settings.gamificationEnabled
                ? 'Vises på forsiden. Slå det fra, hvis det bare stresser.'
                : 'Skjult. Din aktivitet registreres stadig i timelinen.',
            value: settings.gamificationEnabled,
            onChanged: (value) async {
              controller.setGamification(value);
              final current = await ref.read(profileRepositoryProvider).read();
              if (current != null) {
                await ref
                    .read(profileRepositoryProvider)
                    .update(current.copyWith(gamificationEnabled: value));
                ref.read(dataRevisionProvider.notifier).bump();
              }
            },
          ),
        ),

        if (profile != null) ...[
          const SizedBox(height: 28),
          const SectionHeading('Om dig'),
          _ProfileCard(name: profile.displayName, grade: profile.gradeLevel),
        ],

        const SizedBox(height: 28),
        const SectionHeading('Data'),
        Panel(
          onTap: () => nav.go(const PrivacyRoute()),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Privatliv og data',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Hvad appen må, hvad der gemmes, eksport og sletning.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.forward, size: 20, color: context.colors.textTertiary),
            ],
          ),
        ),

        const SizedBox(height: 28),
        const _About(),
      ],
    );
  }
}

class _ApiKeyCard extends ConsumerStatefulWidget {
  const _ApiKeyCard();

  @override
  ConsumerState<_ApiKeyCard> createState() => _ApiKeyCardState();
}

class _ApiKeyCardState extends ConsumerState<_ApiKeyCard> {
  final _field = TextEditingController();
  bool _editing = false;
  bool _checking = false;
  String? _message;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _field.text.trim();
    if (!ApiKeyStore.looksValid(key)) {
      setState(() => _message = 'Det ligner ikke en Anthropic-nøgle. '
          'De starter med "sk-ant-".');
      return;
    }

    setState(() {
      _checking = true;
      _message = null;
    });

    await ref.read(apiKeyProvider.notifier).save(key);
    // Prove the key works before telling the user it is saved.
    final health = await ref.read(aiStackProvider).check();

    if (!mounted) return;
    setState(() {
      _checking = false;
      _editing = health.ok;
      _message = health.ok ? null : health.message;
    });
    if (health.ok) {
      _field.clear();
      ref.invalidate(aiHealthProvider);
      ref.invalidate(suggestionsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = ref.watch(apiKeyProvider);
    final text = Theme.of(context).textTheme;
    final colors = context.colors;
    final health = ref.watch(aiHealthProvider);

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Anthropic API-nøgle', style: text.titleMedium),
              ),
              if (key != null)
                health.when(
                  loading: () => Text('Tjekker …', style: text.labelSmall),
                  error: (_, _) => Tag('Fejl', tone: colors.danger, filled: true),
                  data: (h) => Tag(
                    h.ok ? 'Forbundet' : 'Afvist',
                    tone: h.ok ? colors.positive : colors.danger,
                    filled: true,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            key == null
                ? 'TeenBrain bruger din egen nøgle. Den gemmes i '
                    '${ref.read(apiKeyStoreProvider).location} — ikke i appens '
                    'database — og bruges kun til at tale med Anthropic.'
                : 'Gemt som ${ApiKeyStore.mask(key)} i '
                    '${ref.read(apiKeyStoreProvider).location}.',
            style: text.bodyMedium,
          ),

          if (key == null || _editing) ...[
            const SizedBox(height: 14),
            AppTextField(
              controller: _field,
              hint: 'sk-ant-…',
              obscure: true,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                AppButton(
                  label: _checking ? 'Tjekker …' : 'Gem og test',
                  tone: ButtonTone.primary,
                  onPressed: _checking ? null : _save,
                ),
                if (_editing) ...[
                  const SizedBox(width: 10),
                  AppButton(
                    label: 'Annullér',
                    onPressed: () => setState(() {
                      _editing = false;
                      _message = null;
                      _field.clear();
                    }),
                  ),
                ],
              ],
            ),
          ] else ...[
            const SizedBox(height: 14),
            Row(
              children: [
                AppButton(
                  label: 'Skift nøgle',
                  onPressed: () => setState(() => _editing = true),
                ),
                const SizedBox(width: 10),
                AppButton(
                  label: 'Fjern',
                  tone: ButtonTone.danger,
                  onPressed: () async {
                    await ref.read(apiKeyProvider.notifier).clear();
                    ref.invalidate(aiHealthProvider);
                  },
                ),
              ],
            ),
          ],

          if (_message != null) ...[
            const SizedBox(height: 12),
            InlineError(message: _message!),
          ],

          const SizedBox(height: 16),
          Container(height: 1, color: colors.border),
          const SizedBox(height: 14),
          Text('Hvor får jeg en?', style: text.labelSmall),
          const SizedBox(height: 4),
          SelectableText(
            'console.anthropic.com → Settings → API keys. '
            'Du betaler selv for det, du bruger.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 10),
          Text(
            'Værd at vide: en app med din egen nøgle på din egen maskine er fin '
            'til dig. Skal TeenBrain deles ud til mange, skal nøglen ligge på en '
            'server i stedet — det er ikke bygget.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard({required this.name, required this.grade});

  final String name;
  final String? grade;

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
                Text(name, style: text.titleMedium),
                if (grade != null) ...[
                  const SizedBox(height: 3),
                  Text(grade!, style: text.bodyMedium),
                ],
              ],
            ),
          ),
          AppButton(
            label: 'Redigér',
            onPressed: () => _edit(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final nameField = TextEditingController(text: name);
    final gradeField = TextEditingController(text: grade ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.surface,
        title: const Text('Om dig'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(controller: nameField, hint: 'Dit navn', autofocus: true),
            const SizedBox(height: 12),
            AppTextField(controller: gradeField, hint: 'Klassetrin'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annullér'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Gem'),
          ),
        ],
      ),
    );

    final newName = nameField.text.trim();
    final newGrade = gradeField.text.trim();
    nameField.dispose();
    gradeField.dispose();

    if (saved != true || newName.isEmpty) return;

    final profile = await ref.read(profileRepositoryProvider).read();
    if (profile == null) return;
    await ref.read(profileRepositoryProvider).update(
          profile.copyWith(
            displayName: newName,
            gradeLevel: newGrade.isEmpty ? null : newGrade,
            clearGradeLevel: newGrade.isEmpty,
          ),
        );
    ref.read(dataRevisionProvider.notifier).bump();
  }
}

class _About extends ConsumerWidget {
  const _About();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final index = ref.watch(searchIndexProvider);

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Om TeenBrain', style: text.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Version 1.0 · Alt ligger lokalt på din maskine.\n'
            'Søgning: ${index.hasFullTextSearch ? 'fuldtekst (FTS5)' : 'tekstmatch (fallback)'}',
            style: text.bodySmall,
          ),
          const SizedBox(height: 14),
          AppButton(
            label: 'Genopbyg søgeindeks',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final count = await ref.read(searchIndexProvider).rebuild();
              messenger.showSnackBar(
                SnackBar(
                  content: Text('$count ting indekseret.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
