/// Screen understanding — the consent page.
///
/// Turning this on is a real decision, so it gets a real page rather than a
/// switch buried in a list. The capture layer itself is not built yet, and this
/// page says so instead of offering a toggle that does nothing.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/theme.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class ScreenUnderstandingPage extends ConsumerWidget {
  const ScreenUnderstandingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = context.colors;

    return PageBody(
      children: [
        const PageTitle(
          'Skærmforståelse',
          subtitle: 'Lad appen se hvad du arbejder med — hvis du vil.',
        ),

        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sådan er det tænkt', style: text.titleMedium),
              const SizedBox(height: 10),
              Text(
                'Ser du en matematikopgave på skærmen, kan appen genkende faget, '
                'emnet og opgaven — og tilbyde at hjælpe. Den analyserer et '
                'skærmbillede i hukommelsen og kaster det væk igen. Kun '
                'konklusionen — "matematik, andengradsligninger" — kan gemmes, '
                'og kun hvis du beder om det.',
                style: text.bodyMedium,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reglerne, hvis du slår det til', style: text.titleMedium),
              const SizedBox(height: 12),
              _Rule(
                tone: colors.recording,
                text: 'Der er altid en rød indikator i vinduet, mens den er aktiv. '
                    'Den kan ikke skjules.',
              ),
              _Rule(
                tone: colors.positive,
                text: 'Der optages ikke. Der gemmes ingen billeder, nogensinde.',
              ),
              _Rule(
                tone: colors.positive,
                text: 'Analysen sker lokalt på din maskine med Apples egen Vision. '
                    'Skærmbilleder sendes ikke til nogen.',
              ),
              _Rule(
                tone: colors.positive,
                text: 'macOS viser sin egen skærmoptagelses-indikator. '
                    'Den kan appen ikke slukke — og det er meningen.',
              ),
              _Rule(
                tone: colors.positive,
                text: 'Du kan slå det fra igen når som helst, uden at miste noget.',
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        ComingSoon(
          title: 'Funktionen er ikke bygget endnu',
          explanation: Platform.isMacOS
              ? 'Arkitekturen ligger klar — samme kadence-logik som resten af appen '
                  'bruger, og Apple Vision er allerede i projektet. Men '
                  'skærmoptagelsen er ikke skrevet, og jeg viser hellere det her '
                  'end en kontakt, der lader som om den virker.'
              : 'ScreenCaptureKit findes kun på macOS. På Windows kræver det en '
                  'anden implementering, som ikke er skrevet.',
          missing: [
            if (Platform.isMacOS)
              'ScreenCaptureKit-optagelse med systemets tilladelsesdialog'
            else
              'Windows-skærmoptagelse (Windows.Graphics.Capture)',
            'Tekstgenkendelse på skærmbilledet (VNRecognizeTextRequest)',
            'Genkendelse af fag og emne ud fra det, der står på skærmen',
            'Forslags-boblen: "Vil du have hjælp til den her opgave?"',
          ],
        ),

        const SizedBox(height: 24),
        Row(
          children: [
            AppButton(
              label: 'Tilbage til Privatliv',
              onPressed: () => ref.read(navigationProvider.notifier).go(const PrivacyRoute()),
            ),
          ],
        ),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.tone, required this.text});

  final Color tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
