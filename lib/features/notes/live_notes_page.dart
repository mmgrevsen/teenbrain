/// Live Notes.
///
/// Record a lesson, watch the words arrive, and turn the transcript into
/// structured notes. The recogniser runs on the device, so the audio never
/// leaves the machine — and nothing is written to disk along the way: there is
/// only text in memory until you choose to make a note of it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../brain/live_notes_service.dart';
import '../../domain/models/school.dart';
import '../../domain/services/ai_client.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class LiveNotesPage extends ConsumerStatefulWidget {
  const LiveNotesPage({super.key});

  @override
  ConsumerState<LiveNotesPage> createState() => _LiveNotesPageState();
}

class _LiveNotesPageState extends ConsumerState<LiveNotesPage> {
  final _source = TextEditingController();
  final _scroll = ScrollController();

  int? _subjectId;
  bool _working = false;
  String? _error;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Only to redraw the elapsed timer; the transcript updates itself.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(currentLiveNotesProvider).isListening) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _source.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    final service = ref.read(liveNotesProvider);
    setState(() => _error = null);

    if (ref.read(currentLiveNotesProvider).isListening) {
      final transcript = await service.stop();
      if (!mounted) return;
      // Hand the transcript to the editor, so it can be corrected before it
      // becomes a note. Speech recognition is good, not perfect.
      if (transcript.isNotEmpty) {
        _source.text = _source.text.trim().isEmpty
            ? transcript
            : '${_source.text.trim()}\n\n$transcript';
        service.reset();
      }
      return;
    }

    await service.start();
  }

  Future<void> _structure() async {
    final raw = _source.text.trim();
    if (raw.length < 20) {
      setState(() => _error = 'Der skal lidt mere tekst til.');
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final note = await ref.read(brainProvider).structureNote(
            rawText: raw,
            subjectId: _subjectId,
            sourceLabel: 'Live Notes',
          );
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) return;
      _source.clear();
      ref.read(liveNotesProvider).reset();
      ref.read(navigationProvider.notifier).push(NoteDetailRoute(note.id));
    } on AiFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Kunne ikke lave noten: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(liveNotesProvider);
    final live = ref.watch(currentLiveNotesProvider);
    final settings = ref.watch(settingsProvider);
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final configured = ref.watch(aiStackProvider).isConfigured;
    final text = Theme.of(context).textTheme;

    return PageBody(
      children: [
        const PageTitle(
          'Live Notes',
          subtitle: 'Optag undervisningen, og få den som strukturerede noter.',
        ),

        if (!service.isSupported)
          ComingSoon(
            title: 'Optagelse findes ikke på denne platform',
            explanation: service.unsupportedExplanation,
            missing: const [
              'Talegenkendelse uden for macOS',
            ],
          )
        else if (!settings.microphoneEnabled)
          _MicrophoneOff(onEnable: () {
            ref.read(settingsProvider.notifier).setMicrophone(true);
          })
        else
          _Recorder(
            state: live,
            service: service,
            onToggle: _toggleRecording,
            scroll: _scroll,
          ),

        const SizedBox(height: 26),
        SectionHeading(
          live.hasText || _source.text.trim().isNotEmpty
              ? 'Teksten'
              : 'Eller indsæt tekst selv',
        ),
        Text(
          'Ret gerne i teksten, før du laver noten — talegenkendelse er god, '
          'men ikke perfekt med fagord.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 14),

        if (subjects.isNotEmpty) ...[
          ChoiceRow<int?>(
            selected: _subjectId,
            onSelected: (value) => setState(() => _subjectId = value),
            options: [
              (value: null, label: 'Lad AI\'en gætte faget'),
              for (final subject in subjects) (value: subject.id, label: subject.name),
            ],
          ),
          const SizedBox(height: 14),
        ],

        AppTextField(
          controller: _source,
          hint: 'Indsæt eller skriv teksten her …',
          minLines: 8,
          maxLines: 40,
          padding: const EdgeInsets.all(16),
          enabled: !_working,
          onChanged: (_) => setState(() {}),
        ),

        if (_error != null) ...[
          const SizedBox(height: 14),
          InlineError(message: _error!),
        ],

        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AppButton(
              label: _working ? 'Strukturerer …' : 'Lav noter',
              tone: ButtonTone.primary,
              onPressed: _working || !configured ? null : _structure,
            ),
            if (_source.text.trim().isNotEmpty)
              AppButton(
                label: 'Ryd',
                onPressed: _working
                    ? null
                    : () {
                        _source.clear();
                        ref.read(liveNotesProvider).reset();
                        setState(() => _error = null);
                      },
              ),
          ],
        ),
        if (!configured)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'At lave noter ud af teksten kræver en API-nøgle under Indstillinger. '
              'Optagelsen og talegenkendelsen virker uden.',
              style: text.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Shown when the microphone switch is off. It does not pretend the feature is
/// missing — it says where the switch is, and turns it on from here.
class _MicrophoneOff extends StatelessWidget {
  const _MicrophoneOff({required this.onEnable});
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mic_off_outlined, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 10),
              Expanded(child: Text('Mikrofonen er slået fra', style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Live Notes optager kun, når du selv har slået mikrofonen til. '
            'Talegenkendelsen kører lokalt på din Mac, og lyden bliver hverken '
            'gemt eller sendt nogen steder hen.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AppButton(label: 'Slå mikrofonen til', tone: ButtonTone.primary, onPressed: onEnable),
              Consumer(
                builder: (context, ref, _) => AppButton(
                  label: 'Åbn Privatliv',
                  onPressed: () =>
                      ref.read(navigationProvider.notifier).go(const PrivacyRoute()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The record button, the live transcript and the indicator.
class _Recorder extends StatelessWidget {
  const _Recorder({
    required this.state,
    required this.service,
    required this.onToggle,
    required this.scroll,
  });

  final LiveNotesState state;
  final LiveNotesService service;
  final VoidCallback onToggle;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;
    final elapsed = state.elapsed(DateTime.now());

    return Panel(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RecordButton(
                listening: state.isListening,
                busy: state.isBusy,
                onTap: onToggle,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isListening
                          ? 'Lytter …'
                          : state.isBusy
                              ? 'Et øjeblik …'
                              : 'Klar til at optage',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      state.isListening
                          ? '${_duration(elapsed)} · ${state.wordCount} ord'
                          : '${service.backendLabel} · kører lokalt',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (state.isListening) const _LiveDot(),
            ],
          ),

          if (state.error != null) ...[
            const SizedBox(height: 16),
            InlineError(message: state.error!),
          ],

          if (state.hasText) ...[
            const SizedBox(height: 18),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceHover,
                borderRadius: BorderRadius.circular(Insets.radiusSmall),
              ),
              child: SingleChildScrollView(
                controller: scroll,
                reverse: true,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: state.committed, style: text.bodyLarge),
                    if (state.pending.isNotEmpty)
                      TextSpan(
                        text: state.committed.isEmpty
                            ? state.pending
                            : ' ${state.pending}',
                        // The sentence the recogniser is still revising, so it
                        // is visibly not settled yet.
                        style: text.bodyLarge!.copyWith(color: colors.textTertiary),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              state.isListening
                  ? 'Stop optagelsen, når timen er slut — så kan du rette teksten, '
                      'før den bliver til noter.'
                  : 'Teksten står herunder, klar til at blive rettet.',
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  static String _duration(Duration? d) {
    if (d == null) return '0:00';
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.listening,
    required this.busy,
    required this.onTap,
  });

  final bool listening;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Hoverable(
      onTap: busy ? () {} : onTap,
      builder: (hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: listening ? colors.recording : colors.accent,
          borderRadius: BorderRadius.circular(listening ? 14 : 26),
          boxShadow: hovered && !busy ? colors.elevation : null,
        ),
        child: Opacity(
          opacity: busy ? 0.6 : 1,
          child: Icon(
            listening ? Icons.stop_rounded : Icons.mic_rounded,
            color: Colors.white,
            size: listening ? 22 : 24,
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: colors.recording, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            'OPTAGER',
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: colors.recording,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
          ),
        ],
      ),
    );
  }
}
