/// Global search across everything the user has made.
///
/// Works with no API key: the query is interpreted locally, and the index is
/// local too.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/time_format.dart';
import '../../domain/models/search.dart';
import '../../shared/widgets/page_body.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../../shared/widgets/teenbrain.dart';

class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  SearchOutcome? _outcome;
  bool _searching = false;
  Set<SearchScope>? _scopes;

  static const _examples = [
    'Hvornår lærte jeg om fotosyntese?',
    'Find mine noter om anden verdenskrig',
    'Hvad havde jeg svært ved i matematik sidste måned?',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _query.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _run);
  }

  Future<void> _run() async {
    final text = _query.text.trim();
    if (text.isEmpty) {
      setState(() => _outcome = null);
      return;
    }
    setState(() => _searching = true);
    final outcome = await ref.read(brainProvider).globalSearch(text, scopes: _scopes);
    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _outcome;
    final text = Theme.of(context).textTheme;

    return PageBody(
      children: [
        const PageTitle('Søg', subtitle: 'Noter, samtaler, quizzer, aktiviteter og hukommelse.'),
        AppTextField(
          controller: _query,
          hint: 'Spørg om noget du har lavet …',
          autofocus: true,
          onChanged: (_) => _schedule(),
          onSubmitted: (_) => _run(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          textStyle: text.bodyLarge!.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 14),
        ChoiceRow<Set<SearchScope>?>(
          selected: _scopes,
          onSelected: (value) {
            setState(() => _scopes = value);
            _run();
          },
          options: [
            (value: null, label: 'Alt'),
            (value: {SearchScope.note}, label: 'Noter'),
            (value: {SearchScope.conversation}, label: 'Samtaler'),
            (value: {SearchScope.quiz}, label: 'Quizzer'),
            (value: {SearchScope.timeline}, label: 'Aktivitet'),
            (value: {SearchScope.memory}, label: 'Hukommelse'),
          ],
        ),
        const SizedBox(height: 24),

        if (outcome == null && !_searching) ...[
          Text('Prøv fx', style: text.labelSmall),
          const SizedBox(height: 10),
          for (final example in _examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onTap: () {
                  _query.text = example;
                  _run();
                },
                child: Text(example, style: text.bodyMedium),
              ),
            ),
        ],

        if (_searching && outcome == null)
          const Column(
            children: [
              SkeletonBox(height: 64, radius: Insets.radius),
              SizedBox(height: 8),
              SkeletonBox(height: 64, radius: Insets.radius),
            ],
          ),

        if (outcome != null) ...[
          if (outcome.answer != null) ...[
            Panel(
              accent: true,
              child: Text(outcome.answer!, style: text.bodyLarge),
            ),
            const SizedBox(height: 20),
          ],
          if (outcome.hits.isEmpty && outcome.answer == null)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: EmptyState(
                icon: AppIcons.search,
                title: 'Ingen resultater',
                message: outcome.interpretation.terms.isEmpty
                    ? 'Prøv med et par konkrete ord fra det, du leder efter.'
                    : 'Der er ikke noget om '
                        '"${outcome.interpretation.terms.join(' ')}" endnu.',
              ),
            )
          else ...[
            Text(
              '${outcome.hits.length} '
              '${outcome.hits.length == 1 ? 'resultat' : 'resultater'}',
              style: text.labelSmall,
            ),
            const SizedBox(height: 10),
            for (final hit in outcome.hits)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _HitCard(hit: hit),
              ),
          ],
        ],
      ],
    );
  }
}

class _HitCard extends ConsumerWidget {
  const _HitCard({required this.hit});
  final SearchHit hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return Panel(
      onTap: () => _open(ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tag(hit.scope.label),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hit.title,
                  style: text.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Text(shortAgo(hit.occurredAt), style: text.bodySmall),
            ],
          ),
          if (hit.snippet.isNotEmpty && hit.snippet != hit.title) ...[
            const SizedBox(height: 7),
            Text(
              hit.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium,
            ),
          ],
          if (hit.subjectName != null) ...[
            const SizedBox(height: 8),
            Text(hit.subjectName!, style: text.labelSmall),
          ],
        ],
      ),
    );
  }

  void _open(WidgetRef ref) {
    final nav = ref.read(navigationProvider.notifier);
    switch (hit.scope) {
      case SearchScope.note:
        nav.push(NoteDetailRoute(hit.refId));
      case SearchScope.conversation:
        nav.push(ChatRoute(conversationId: hit.refId));
      case SearchScope.quiz:
        nav.push(QuizRunRoute(hit.refId));
      case SearchScope.assignment:
      case SearchScope.timeline:
        if (hit.subjectId != null) {
          nav.push(SubjectDetailRoute(hit.subjectId!));
        } else {
          nav.push(const TimelineRoute());
        }
      case SearchScope.memory:
        nav.push(const MyAiRoute());
    }
  }
}
