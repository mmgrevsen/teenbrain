import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/services/answer_engine.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/search_field.dart';
import '../../vision/taxonomy/object_taxonomy.dart';

/// Ask a question in plain Danish, get one sentence back — plus the evidence
/// it was built from, so the answer can be checked rather than believed.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery ?? '');

  MemoryAnswer? _answer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if ((widget.initialQuery ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(widget.initialQuery!));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _busy = true);
    final engine = ref.read(answerEngineProvider);
    final answer = await engine.answer(query);
    if (!mounted) return;
    setState(() {
      _answer = answer;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final nav = ref.read(navigationProvider.notifier);
    final answer = _answer;

    return PageBody(
      padding: const EdgeInsets.fromLTRB(Insets.page, 24, Insets.page, 56),
      children: [
        const PageTitle('Søg', subtitle: 'Spørg om hvor som helst du har lagt noget.'),
        SearchField(
          controller: _controller,
          autofocus: true,
          large: true,
          onSubmit: _run,
        ),
        const SizedBox(height: 28),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (answer != null) ...[
          _AnswerCard(answer: answer),
          if (answer.primary != null) ...[
            const SizedBox(height: 28),
            const SectionHeading('Observationen bag svaret'),
            Panel(
              padding: const EdgeInsets.all(6),
              child: ObservationRow(
                time: answer.primary!.seenAt,
                objectLabel: answer.primary!.objectLabel,
                icon: ObjectTaxonomy.standard.kindByKey(answer.primary!.objectKey)?.icon ?? '▢',
                placeLabel: answer.primary!.placeLabel,
                confidence: answer.primary!.confidence,
                imagePath: answer.primary!.imagePath,
                bounds: answer.primary!.bounds,
                onTap: () => nav.push(ObservationDetailRoute(answer.primary!.id)),
              ),
            ),
          ],
          if (answer.supporting.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionHeading('Tidligere gange'),
            Panel(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  for (final o in answer.supporting)
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
          ],
          if (answer.caveat != null) ...[
            const SizedBox(height: 16),
            _HabitNote(text: answer.caveat!),
          ],
          if (answer.habit != null && answer.habit!.isStrong) ...[
            const SizedBox(height: 24),
            _HabitNote(
              text: '${answer.query.objectLabel ?? 'Objektet'} bliver oftest set '
                  '${answer.habit!.placeLabel.toLowerCase()} '
                  '(${answer.habit!.count} af ${answer.habit!.totalForObject} gange).',
            ),
          ],
        ] else
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 18),
            child: EmptyState(
              glyph: '⌕',
              title: 'Stil et spørgsmål',
              message: 'Prøv “Hvor er mine AirPods?”, “Hvornår så jeg min telefon?” '
                  'eller “Hvad ligger på skrivebordet?”.',
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Søgningen kører lokalt på denne computer. Der bliver ikke sendt noget til nettet.',
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer});
  final MemoryAnswer answer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Panel(
      accent: answer.isConfident,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'GlemtDet',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: answer.isConfident ? colors.accent : colors.textTertiary,
                      letterSpacing: 0.8,
                    ),
              ),
              const Spacer(),
              if (!answer.isConfident)
                Text(
                  'usikkert',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(color: colors.warning),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            answer.text,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  fontSize: 17,
                  height: 1.45,
                  color: colors.textPrimary,
                ),
          ),
          if (answer.primary != null) ...[
            const SizedBox(height: 14),
            Text(
              'Baseret på en observation ${whenPhrase(answer.primary!.seenAt)} '
              'med ${(answer.primary!.confidence * 100).round()} % sikkerhed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _HabitNote extends StatelessWidget {
  const _HabitNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(Insets.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('◈', style: TextStyle(color: colors.textTertiary, fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
