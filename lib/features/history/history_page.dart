import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/models/observation.dart';
import '../../domain/repositories/memory_repository.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../vision/taxonomy/object_taxonomy.dart';

/// Everything GlemtDet has written down, newest first, grouped by day.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String? _objectFilter;

  @override
  Widget build(BuildContext context) {
    final nav = ref.read(navigationProvider.notifier);
    final filter = HistoryFilter(objectKey: _objectFilter, limit: 300);
    final history = ref.watch(historyProvider(filter));
    final objects = ref.watch(trackedObjectsProvider).value ?? const <TrackedObject>[];

    return PageBody(
      padding: const EdgeInsets.fromLTRB(Insets.page, 16, Insets.page, 56),
      children: [
        const PageTitle('Historik', subtitle: 'Alle observationer, nyeste først.'),
        if (objects.isNotEmpty) ...[
          _FilterBar(
            objects: objects,
            selected: _objectFilter,
            onSelect: (key) => setState(() => _objectFilter = key),
          ),
          const SizedBox(height: 20),
        ],
        history.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
          error: (e, _) => Panel(child: Text('Kunne ikke læse historikken: $e')),
          data: (observations) {
            if (observations.isEmpty) {
              return Panel(
                padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 18),
                child: const EmptyState(
                  glyph: '◷',
                  title: 'Ingen observationer',
                  message: 'Når scanneren har kørt, dukker der observationer op her.',
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in _groupByDay(observations)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 10),
                    child: Text(
                      group.heading,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Panel(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      children: [
                        for (final o in group.items)
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
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  static List<_DayGroup> _groupByDay(List<Observation> observations) {
    final groups = <_DayGroup>[];
    for (final o in observations) {
      final heading = dayHeading(o.seenAt);
      if (groups.isEmpty || groups.last.heading != heading) {
        groups.add(_DayGroup(heading, [o]));
      } else {
        groups.last.items.add(o);
      }
    }
    return groups;
  }
}

class _DayGroup {
  _DayGroup(this.heading, this.items);
  final String heading;
  final List<Observation> items;
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.objects, required this.selected, required this.onSelect});

  final List<TrackedObject> objects;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChip(label: 'Alle', active: selected == null, onTap: () => onSelect(null)),
        for (final o in objects.take(12))
          _FilterChip(
            label: o.label,
            active: selected == o.key,
            onTap: () => onSelect(selected == o.key ? null : o.key),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? colors.accentSoft : colors.surface,
            border: Border.all(color: active ? colors.accent.withValues(alpha: 0.4) : colors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  color: active ? colors.accent : colors.textSecondary,
                ),
          ),
        ),
      ),
    );
  }
}
