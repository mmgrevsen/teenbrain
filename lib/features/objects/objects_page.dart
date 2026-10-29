import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../vision/taxonomy/object_taxonomy.dart';

/// Everything GlemtDet believes you own, because it has seen it.
class ObjectsPage extends ConsumerWidget {
  const ObjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final objects = ref.watch(trackedObjectsProvider);
    final nav = ref.read(navigationProvider.notifier);

    return PageBody(
      padding: const EdgeInsets.fromLTRB(Insets.page, 16, Insets.page, 56),
      children: [
        const PageTitle(
          'Objekter',
          subtitle: 'Ting GlemtDet har genkendt mindst én gang.',
        ),
        objects.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
          error: (e, _) => Panel(child: Text('Kunne ikke læse objekter: $e')),
          data: (items) {
            if (items.isEmpty) {
              return Panel(
                padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 18),
                child: const EmptyState(
                  glyph: '▣',
                  title: 'Ingen objekter endnu',
                  message: 'GlemtDet lærer dine ting at kende, efterhånden som scanneren '
                      'ser dem.',
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 620 ? 3 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.35,
                  ),
                  itemBuilder: (context, index) {
                    final object = items[index];
                    return Panel(
                      onTap: () => nav.push(ObjectDetailRoute(object.key)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                ObjectTaxonomy.standard.kindByKey(object.key)?.icon ?? '▢',
                                style: TextStyle(
                                  fontSize: 17,
                                  color: context.colors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  object.label,
                                  style: Theme.of(context).textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            object.lastPlaceLabel ?? 'Ukendt placering',
                            style: Theme.of(context).textTheme.bodyLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${shortAgo(object.lastSeen)} · ${object.observationCount} '
                            '${object.observationCount == 1 ? 'observation' : 'observationer'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}
