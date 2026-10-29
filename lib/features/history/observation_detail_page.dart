import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/danish.dart';
import '../../core/time_format.dart';
import '../../domain/models/detection.dart';
import '../../domain/models/observation.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../vision/taxonomy/object_taxonomy.dart';

/// One observation in full: the frame, the reasoning, and what else was in
/// view at the same moment.
class ObservationDetailPage extends ConsumerWidget {
  const ObservationDetailPage({super.key, required this.observationId});
  final int observationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(memoryRepositoryProvider);
    ref.watch(memoryRevisionProvider);

    return FutureBuilder<Observation?>(
      future: repository.observationById(observationId),
      builder: (context, snapshot) {
        if (!snapshot.hasData && snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final observation = snapshot.data;
        if (observation == null) {
          return const PageBody(children: [
            EmptyState(
              glyph: '⌧',
              title: 'Observationen findes ikke',
              message: 'Den er formentlig blevet slettet.',
            ),
          ]);
        }
        return _Detail(observation: observation);
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.observation});
  final Observation observation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(navigationProvider.notifier);
    final colors = context.colors;
    final repository = ref.watch(memoryRepositoryProvider);
    final grammar = placeGrammarFor(observation.placeKey);

    return PageBody(
      padding: const EdgeInsets.fromLTRB(Insets.page, 16, Insets.page, 56),
      children: [
        PageTitle(
          observation.objectLabel,
          subtitle: '${dayHeading(observation.seenAt)} · ${whenPhrase(observation.seenAt)}',
          trailing: AppButton(
            label: 'Slet',
            tone: ButtonTone.danger,
            onPressed: () async {
              await repository.deleteObservation(observation.id);
              ref.read(memoryRevisionProvider.notifier).bump();
              nav.pop();
            },
          ),
        ),
        if (observation.imagePath != null)
          _FullFrame(path: observation.imagePath!, bounds: observation.bounds)
        else
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                'Der blev ikke gemt et billede til denne observation.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _FactPanel(
                facts: [
                  ('Objekt', observation.objectLabel),
                  ('Tidspunkt', '${clockOf(observation.seenAt)} · ${dayHeading(observation.seenAt)}'),
                  (
                    'Placering',
                    observation.placeLabel == null
                        ? 'Kunne ikke bestemmes'
                        : grammar == null
                            ? observation.placeLabel!
                            : '${observation.placeLabel!} (${grammar.located})'
                  ),
                  ('Sikkerhed', '${(observation.confidence * 100).round()} %'),
                  if (observation.placeConfidence != null)
                    ('Sikkerhed på placering', '${(observation.placeConfidence! * 100).round()} %'),
                  ('Analyseret af', observation.backend),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: _EvidencePanel(labels: observation.rawLabels)),
          ],
        ),
        const SizedBox(height: 22),
        const SectionHeading('Set samtidig'),
        FutureBuilder<List<Observation>>(
          future: repository.around(observation.seenAt, excludeId: observation.id),
          builder: (context, snapshot) {
            final related = snapshot.data ?? const <Observation>[];
            if (related.isEmpty) {
              return Panel(
                child: Text(
                  'Ingen andre observationer omkring dette tidspunkt.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            return Panel(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  for (final o in related)
                    ObservationRow(
                      time: o.seenAt,
                      objectLabel: o.objectLabel,
                      icon: ObjectTaxonomy.standard.kindByKey(o.objectKey)?.icon ?? '▢',
                      placeLabel: o.placeLabel,
                      confidence: o.confidence,
                      imagePath: o.imagePath,
                      bounds: o.bounds,
                      onTap: () => nav.push(ObservationDetailRoute(o.id)),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        AppButton(
          label: 'Se alt om ${observation.objectLabel}',
          onPressed: () => nav.push(ObjectDetailRoute(observation.objectKey)),
        ),
        const SizedBox(height: 16),
        Text(
          'Billedet ligger kun på denne computer, i GlemtDets egen datamappe.',
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _FullFrame extends StatelessWidget {
  const _FullFrame({required this.path, this.bounds});
  final String path;
  final NormRect? bounds;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) {
      return Panel(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Text(
            'Billedet er slettet fra disken.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(Insets.radius),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(file, fit: BoxFit.cover),
            if (bounds != null)
              CustomPaint(painter: _BoundsPainter(bounds!, context.colors.accent)),
          ],
        ),
      ),
    );
  }
}

class _BoundsPainter extends CustomPainter {
  _BoundsPainter(this.rect, this.color);
  final NormRect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      rect.left * size.width,
      rect.top * size.height,
      rect.width * size.width,
      rect.height * size.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(4)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_BoundsPainter old) => old.rect != rect;
}

class _FactPanel extends StatelessWidget {
  const _FactPanel({required this.facts});
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading('Detaljer'),
          for (final (label, value) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  Expanded(
                    child: Text(value, style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The raw backend labels. Shown so the user can see *why* GlemtDet decided
/// what it decided instead of having to trust a number.
class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({required this.labels});
  final List<RawLabel> labels;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading('Grundlag'),
          if (labels.isEmpty)
            Text('Ingen labels gemt.', style: Theme.of(context).textTheme.bodyMedium)
          else
            for (final label in labels.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label.identifier,
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                      ),
                    ),
                    ConfidencePill(confidence: label.confidence),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
