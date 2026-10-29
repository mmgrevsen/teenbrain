import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/danish.dart';
import '../../core/time_format.dart';
import '../../domain/models/observation.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../vision/taxonomy/object_taxonomy.dart';

/// One object's whole story: where it is now, where it usually is, and every
/// time GlemtDet has seen it.
class ObjectDetailPage extends ConsumerWidget {
  const ObjectDetailPage({super.key, required this.objectKey});
  final String objectKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final object = ref.watch(trackedObjectProvider(objectKey));
    final observations = ref.watch(objectObservationsProvider(objectKey));
    final habits = ref.watch(objectHabitsProvider(objectKey));
    final nav = ref.read(navigationProvider.notifier);
    final repository = ref.watch(memoryRepositoryProvider);

    final tracked = object.value;
    final items = observations.value ?? const <Observation>[];
    final latest = items.isEmpty ? null : items.first;

    if (object.isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (tracked == null) {
      return const PageBody(children: [
        EmptyState(
          glyph: '⌧',
          title: 'Objektet findes ikke længere',
          message: 'Det er blevet slettet fra hukommelsen.',
        ),
      ]);
    }

    final grammar = placeGrammarFor(latest?.placeKey);

    return PageBody(
      padding: const EdgeInsets.fromLTRB(Insets.page, 16, Insets.page, 56),
      children: [
        PageTitle(
          tracked.label,
          subtitle: '${ObjectTaxonomy.standard.kindByKey(objectKey)?.icon ?? ''}  '
              '${tracked.observationCount} '
              '${tracked.observationCount == 1 ? 'observation' : 'observationer'} · '
              'kendt siden ${dayHeading(tracked.firstSeen).toLowerCase()}',
          trailing: AppButton(
            label: 'Glem dette objekt',
            tone: ButtonTone.danger,
            onPressed: () async {
              await repository.deleteObject(objectKey);
              ref.read(memoryRevisionProvider.notifier).bump();
              nav.pop();
            },
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Panel(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeading('Sidst set'),
                    Text(
                      latest == null ? '—' : whenPhrase(latest.seenAt),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 18),
                    const SectionHeading('Placering'),
                    Text(
                      latest?.placeLabel ?? 'Kunne ikke bestemmes',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (grammar != null && latest?.placeCertainty == PlaceCertainty.approximate) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Jeg så ${grammar.locatedVague}, men kunne ikke afgøre præcis hvor.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    if (latest != null) ...[
                      const SizedBox(height: 16),
                      ConfidencePill(confidence: latest.confidence, label: 'Sikkerhed'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Panel(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FrameThumbnail(
                      path: latest?.imagePath,
                      bounds: latest?.bounds,
                      width: double.infinity,
                      height: 150,
                      radius: 8,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text(
                        latest?.imagePath == null
                            ? 'Intet gemt billede'
                            : 'Seneste billede',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        habits.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) {
            final strong = list.where((h) => h.isStrong).toList();
            if (strong.isEmpty) {
              return Panel(
                child: Text(
                  'GlemtDet har endnu ikke set ${tracked.label.toLowerCase()} nok gange '
                  'til at kende et mønster.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }
            final top = strong.first;
            final topGrammar = placeGrammarFor(top.placeKey);
            return Panel(
              accent: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeading('Mønster'),
                  Text(
                    '${tracked.label} bliver oftest set '
                    '${topGrammar?.located ?? top.placeLabel.toLowerCase()} '
                    '— ${top.count} af ${top.totalForObject} gange.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final habit in list.take(4))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(habit.placeLabel,
                                style: Theme.of(context).textTheme.bodyMedium),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: habit.share,
                                minHeight: 6,
                                backgroundColor: context.colors.border,
                                color: context.colors.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('${(habit.share * 100).round()} %',
                              style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        const SectionHeading('Seneste observationer'),
        if (items.isEmpty)
          Panel(child: Text('Ingen observationer.', style: Theme.of(context).textTheme.bodyMedium))
        else
          Panel(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                for (final o in items)
                  ObservationRow(
                    time: o.seenAt,
                    objectLabel: dayHeading(o.seenAt),
                    icon: ObjectTaxonomy.standard.kindByKey(o.objectKey)?.icon ?? '▢',
                    placeLabel: o.placeLabel,
                    confidence: o.confidence,
                    imagePath: o.imagePath,
                    bounds: o.bounds,
                    onTap: () => nav.push(ObservationDetailRoute(o.id)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
