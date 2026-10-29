import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/system_bridge.dart';
import '../../app/theme.dart';
import '../../data/settings_store.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../vision/taxonomy/blind_spots.dart';
import '../../vision/taxonomy/object_taxonomy.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String? _notice;

  void _notify(String message) => setState(() => _notice = message);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final stats = ref.watch(storageStatsProvider);
    final stack = ref.watch(visionStackProvider);
    final devices = ref.watch(cameraDevicesProvider);
    final colors = context.colors;

    return PageBody(
      padding: const EdgeInsets.fromLTRB(Insets.page, 16, Insets.page, 56),
      children: [
        const PageTitle('Indstillinger'),

        // ---------------------------------------------------------- privacy
        const SectionHeading('Data'),
        Panel(
          child: Column(
            children: [
              _Row(
                title: 'Kun på denne computer',
                description: 'GlemtDet gemmer alt lokalt i sin egen datamappe. '
                    'Der er ingen konto, ingen sky og ingen netværkskald i appen.',
                trailing: _LockedOn(),
              ),
              _Divider(),
              _Row(
                title: 'Gem billeder',
                description: 'Slå fra hvis GlemtDet kun må huske tekst — objekt, '
                    'tidspunkt og placering — uden reference-billeder.',
                trailing: Switch(
                  value: settings.storeImages,
                  activeThumbColor: colors.accent,
                  onChanged: (v) {
                    controller.setStoreImages(v);
                    ref.read(memoryServiceProvider).storeImages = v;
                  },
                ),
              ),
              _Divider(),
              _Row(
                title: 'Pause hukommelse',
                description: 'Scanneren kan køre uden at skrive noget ned.',
                trailing: Switch(
                  value: !settings.memoryActive,
                  activeThumbColor: colors.accent,
                  onChanged: (paused) async {
                    controller.setMemoryActive(!paused);
                    final service = ref.read(memoryServiceProvider);
                    if (paused) {
                      await service.stop();
                    } else {
                      await service.start(deviceId: settings.cameraDeviceId);
                    }
                  },
                ),
              ),
              _Divider(),
              _Row(
                title: 'Behold historik',
                description: 'Ældre observationer og deres billeder slettes automatisk.',
                trailing: _RetentionPicker(
                  value: settings.retentionDays,
                  onChanged: (days) async {
                    controller.setRetentionDays(days);
                    if (days > 0) {
                      final removed = await ref.read(memoryRepositoryProvider).pruneBefore(
                            DateTime.now().subtract(Duration(days: days)),
                          );
                      ref.read(memoryRevisionProvider.notifier).bump();
                      if (removed > 0) _notify('Slettede $removed gamle observationer.');
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        stats.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (s) => Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeading('Hvad ligger der'),
                _Fact('Observationer', '${s.observationCount}'),
                _Fact('Objekter', '${s.objectCount}'),
                _Fact('Placeringer', '${s.placeCount}'),
                _Fact('Gemte billeder', '${s.imageCount} · ${_bytes(s.imageBytes)}'),
                _Fact('Database', _bytes(s.databaseBytes)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButton(
                      label: 'Eksportér data',
                      onPressed: () => _export(context),
                    ),
                    AppButton(
                      label: 'Vis datamappe',
                      onPressed: () async {
                        final dir = glemtDetDataDirectory();
                        final opened = await SystemBridge.reveal(dir.path);
                        if (!opened) _notify(dir.path);
                      },
                    ),
                    AppButton(
                      label: 'Slet alle billeder',
                      tone: ButtonTone.danger,
                      onPressed: () => _confirm(
                        context,
                        title: 'Slet alle billeder?',
                        body: 'Reference-billederne fjernes fra disken. '
                            'Observationerne — objekt, tidspunkt og placering — bevares.',
                        onConfirm: () async {
                          await ref.read(memoryRepositoryProvider).eraseImages();
                          ref.read(memoryRevisionProvider.notifier).bump();
                          _notify('Alle billeder er slettet.');
                        },
                      ),
                    ),
                    AppButton(
                      label: 'Slet al historik',
                      tone: ButtonTone.danger,
                      onPressed: () => _confirm(
                        context,
                        title: 'Slet alt?',
                        body: 'Hver observation, hvert objekt, hver placering og hvert '
                            'billede slettes permanent. Det kan ikke fortrydes.',
                        onConfirm: () async {
                          await ref.read(memoryRepositoryProvider).eraseAll();
                          ref.read(memoryRevisionProvider.notifier).bump();
                          _notify('Hukommelsen er tømt.');
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ----------------------------------------------------------- camera
        const SizedBox(height: 28),
        const SectionHeading('Kamera og baggrund'),
        Panel(
          child: Column(
            children: [
              _Row(
                title: 'Kamera',
                description: stack.camera.isSupported
                    ? 'Vælg hvilket kamera GlemtDet skal bruge.'
                    : stack.camera.unsupportedExplanation,
                trailing: devices.when(
                  loading: () => const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, _) => const Text('—'),
                  data: (list) => list.isEmpty
                      ? Text('Ingen fundet', style: Theme.of(context).textTheme.bodyMedium)
                      : DropdownButton<String>(
                          value: settings.cameraDeviceId ??
                              list.firstWhere((d) => d.isDefault, orElse: () => list.first).id,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final d in list)
                              DropdownMenuItem(value: d.id, child: Text(d.name)),
                          ],
                          onChanged: (v) => controller.setCameraDevice(v),
                        ),
                ),
              ),
              _Divider(),
              _Row(
                title: 'Fortsæt i baggrunden',
                description: _backgroundExplanation,
                trailing: Switch(
                  value: settings.keepRunningInBackground,
                  activeThumbColor: colors.accent,
                  onChanged: (v) {
                    controller.setBackground(v);
                    ref.read(memoryServiceProvider).setBackgroundMode(false);
                  },
                ),
              ),
            ],
          ),
        ),

        // -------------------------------------------------------- ai engine
        const SizedBox(height: 28),
        const SectionHeading('AI'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Fact('Motor', stack.analyzer.backendDescription),
              _Fact('Kører', stack.camera.isSupported ? 'Lokalt på denne computer' : 'Ikke tilgængelig'),
              _Fact('Svarmotor', 'Lokal dansk sprogmodel-fri søgning'),
              const SizedBox(height: 10),
              Text(
                'AI-laget er bygget bag interfaces, så en anden lokal model — Core ML, '
                'ONNX Runtime eller ML Kit — kan sættes ind uden at røre resten af appen.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              const _VocabularyCheck(),
              const SizedBox(height: 14),
              const _BlindSpots(),
            ],
          ),
        ),

        // ---------------------------------------------------------- display
        const SizedBox(height: 28),
        const SectionHeading('Udseende'),
        Panel(
          child: _Row(
            title: 'Tema',
            description: 'Følg systemet, eller vælg selv.',
            trailing: SegmentedButton<AppThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: AppThemeMode.system, label: Text('System')),
                ButtonSegment(value: AppThemeMode.light, label: Text('Lyst')),
                ButtonSegment(value: AppThemeMode.dark, label: Text('Mørkt')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => controller.setThemeMode(s.first),
            ),
          ),
        ),

        if (_notice != null) ...[
          const SizedBox(height: 20),
          Panel(
            accent: true,
            child: Row(
              children: [
                Expanded(child: SelectableText(_notice!, style: Theme.of(context).textTheme.bodyMedium)),
                AppButton(label: 'OK', onPressed: () => setState(() => _notice = null)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static const String _backgroundExplanation =
      'macOS lader GlemtDet holde kameraet åbent, mens vinduet er lukket, så længe '
      'appen stadig kører — den grønne kameraindikator forbliver tændt, hvilket er '
      'med vilje. Systemet tillader ikke, at en app optager efter den er afsluttet, '
      'og GlemtDet forsøger ikke at omgå det.';

  Future<void> _export(BuildContext context) async {
    final repository = ref.read(memoryRepositoryProvider);
    final data = await repository.exportAll();
    final target = await SystemBridge.exportDirectory();

    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File(p.join(target.path, 'GlemtDet-eksport-$stamp.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    // Reveal it if we can; otherwise the path itself is the useful answer.
    await SystemBridge.reveal(file.path);
    _notify('Eksporteret til ${file.path}');
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onConfirm,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        content: Text(body, style: Theme.of(context).textTheme.bodyMedium),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annullér')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Slet', style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await onConfirm();
  }

  static String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Verifies the Danish taxonomy against the vocabulary the backend can really
/// emit, instead of assuming the mapping is right.
class _VocabularyCheck extends ConsumerWidget {
  const _VocabularyCheck();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vocabulary = ref.watch(backendVocabularyProvider);
    return vocabulary.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return Text(
            'Motoren kan ikke oplyse sit ordforråd på denne platform.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        final taxonomy = ObjectTaxonomy.standard;
        final covered = taxonomy.kinds
            .where((k) => taxonomy.coverageFor(k.key, list).isNotEmpty)
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Motoren kender ${list.length} kategorier. GlemtDet kan genkende '
              '$covered af sine ${taxonomy.kinds.length} objekttyper med den.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (covered < taxonomy.kinds.length) ...[
              const SizedBox(height: 4),
              Text(
                'Uden dækning: ${taxonomy.kinds.where((k) => taxonomy.coverageFor(k.key, list).isEmpty).map((k) => k.label).join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.description, required this.trailing});
  final String title;
  final String description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(description, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: 20),
          trailing,
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Container(height: 1, color: context.colors.border),
      );
}

class _LockedOn extends StatelessWidget {
  const _LockedOn();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.positive.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Altid til',
        style: Theme.of(context).textTheme.labelSmall!.copyWith(color: colors.positive),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 160, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _RetentionPicker extends StatelessWidget {
  const _RetentionPicker({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: value,
      underline: const SizedBox.shrink(),
      items: const [
        DropdownMenuItem(value: 0, child: Text('For altid')),
        DropdownMenuItem(value: 7, child: Text('7 dage')),
        DropdownMenuItem(value: 30, child: Text('30 dage')),
        DropdownMenuItem(value: 90, child: Text('90 dage')),
      ],
      onChanged: (v) => onChanged(v ?? 0),
    );
  }
}

/// Names what the running model cannot do. A user who knows the app will never
/// find their keys can stop waiting for it to happen.
class _BlindSpots extends StatelessWidget {
  const _BlindSpots();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.07),
        border: Border.all(color: colors.warning.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(Insets.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Det her kan jeg ikke',
            style: Theme.of(context).textTheme.titleSmall!.copyWith(color: colors.warning),
          ),
          const SizedBox(height: 8),
          for (final spot in kAppleVisionBlindSpots)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spot.label, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(spot.explanation, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
