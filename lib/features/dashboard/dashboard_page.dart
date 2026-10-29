import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/models/observation.dart';
import '../../domain/services/memory_service.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/search_field.dart';
import '../../vision/taxonomy/object_taxonomy.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(navigationProvider.notifier);
    final recent = ref.watch(recentObservationsProvider);
    final memory = ref.watch(currentMemoryStateProvider);
    final stack = ref.watch(visionStackProvider);
    final colors = context.colors;

    return PageBody(
      padding: const EdgeInsets.fromLTRB(Insets.page, 24, Insets.page, 56),
      children: [
        Text(greeting(), style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 6),
        Text(
          'Hvad leder du efter?',
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 22),
        SearchField(
          large: true,
          hint: 'Hvor er mine AirPods?',
          onSubmit: (value) {
            if (value.trim().isEmpty) return;
            nav.push(SearchRoute(initialQuery: value));
          },
        ),
        const SizedBox(height: 14),
        _Suggestions(onPick: (q) => nav.push(SearchRoute(initialQuery: q))),
        const SizedBox(height: 40),
        const SectionHeading('Senest set'),
        recent.when(
          loading: () => const _LoadingRows(),
          error: (e, _) => Panel(child: Text('Kunne ikke læse hukommelsen: $e')),
          data: (observations) {
            if (observations.isEmpty) {
              return Panel(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 18),
                child: EmptyState(
                  glyph: '◉',
                  title: 'Hukommelsen er tom',
                  message: stack.isLive
                      ? 'Åbn scanneren og lad GlemtDet kigge på dine omgivelser. '
                          'Så begynder den at huske hvor tingene ligger.'
                      : 'Live-scanning er ikke tilgængelig på denne platform, '
                          'så der kommer ikke nye observationer ind automatisk.',
                  action: stack.isLive
                      ? AppButton(
                          label: 'Åbn scanner',
                          tone: ButtonTone.primary,
                          onPressed: () => nav.go(const ScannerRoute()),
                        )
                      : null,
                ),
              );
            }
            return Panel(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  for (final o in observations)
                    ObservationRow(
                      time: o.seenAt,
                      objectLabel: o.objectLabel,
                      icon: _iconFor(o.objectKey),
                      placeLabel: o.placeLabel,
                      confidence: o.confidence,
                      imagePath: o.imagePath,
                      bounds: o.bounds,
                      onTap: () => nav.push(ObjectDetailRoute(o.objectKey)),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            AppButton(
              label: memory.status == MemoryStatus.active ? 'Gå til scanner' : 'Åbn scanner',
              icon: '◉',
              tone: ButtonTone.primary,
              onPressed: () => nav.go(const ScannerRoute()),
            ),
            const SizedBox(width: 10),
            AppButton(
              label: 'Se historik',
              icon: '◷',
              onPressed: () => nav.go(const HistoryRoute()),
            ),
          ],
        ),
        if (!stack.isLive) ...[
          const SizedBox(height: 24),
          _PlatformNotice(message: stack.camera.unsupportedExplanation),
        ],
      ],
    );
  }

  static String _iconFor(String key) =>
      ObjectTaxonomy.standard.kindByKey(key)?.icon ?? '▢';
}

class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final objects = ref.watch(trackedObjectsProvider).value ?? const <TrackedObject>[];
    final suggestions = objects.isEmpty
        ? const ['Hvor er mine AirPods?', 'Hvor så jeg mine nøgler?', 'Har du set min telefon?']
        : objects.take(3).map((o) => 'Hvor er ${o.label.toLowerCase()}?').toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in suggestions)
          _Chip(label: s, onTap: () => onPick(s)),
      ],
    );
  }
}

class _Chip extends StatefulWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHover : colors.surface,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(widget.label, style: Theme.of(context).textTheme.labelMedium),
        ),
      ),
    );
  }
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.textTertiary),
        ),
      ),
    );
  }
}

class _PlatformNotice extends StatelessWidget {
  const _PlatformNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(Insets.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⚠', style: TextStyle(color: colors.warning, fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
