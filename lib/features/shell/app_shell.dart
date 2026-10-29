/// Sidebar plus content on a desktop; bottom navigation on a phone.
///
/// Both layouts render the same pages from the same providers — only the
/// chrome differs, which is why adding mobile did not mean forking the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/primitives.dart';
import '../chat/chat_page.dart';
import '../dashboard/dashboard_page.dart';
import '../focus/focus_page.dart';
import '../history/history_page.dart';
import '../history/observation_detail_page.dart';
import '../home/home_page.dart';
import '../myai/my_ai_page.dart';
import '../notes/live_notes_page.dart';
import '../notes/note_detail_page.dart';
import '../notes/notes_page.dart';
import '../objects/object_detail_page.dart';
import '../objects/objects_page.dart';
import '../privacy/privacy_page.dart';
import '../privacy/screen_understanding_page.dart';
import '../quiz/quiz_result_page.dart';
import '../quiz/quiz_run_page.dart';
import '../quiz/quizzes_page.dart';
import '../scanner/scanner_page.dart';
import '../search/global_search_page.dart';
import '../settings/app_settings_page.dart';
import '../subjects/subject_detail_page.dart';
import '../subjects/subjects_page.dart';
import '../timeline/timeline_page.dart';

/// The destinations that appear in navigation, in order.
///
/// The sidebar shows all of them; the bottom bar shows the first four plus
/// "Mere", because five is the most a thumb can hit reliably.
const _destinations = <_Destination>[
  _Destination(SidebarSection.home, 'Hjem', AppIcons.home, HomeRoute()),
  _Destination(SidebarSection.chat, 'Chat', AppIcons.chat, ChatRoute()),
  _Destination(SidebarSection.subjects, 'Fag', AppIcons.subjects, SubjectsRoute()),
  _Destination(SidebarSection.notes, 'Noter', AppIcons.notes, NotesRoute()),
  _Destination(SidebarSection.quizzes, 'Quiz', AppIcons.quiz, QuizzesRoute()),
  _Destination(SidebarSection.timeline, 'Timeline', AppIcons.timeline, TimelineRoute()),
  _Destination(SidebarSection.myAi, 'Min AI', AppIcons.myAi, MyAiRoute()),
];

class _Destination {
  const _Destination(this.section, this.label, this.icon, this.route);
  final SidebarSection section;
  final String label;
  final IconData icon;
  final AppRoute route;
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final compact = context.isCompact;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: compact ? const _CompactLayout() : const _WideLayout(),
    );
  }

  static Widget pageFor(AppRoute route) => switch (route) {
        HomeRoute() => const HomePage(),
        ChatRoute(:final conversationId, :final initialMessage) =>
          ChatPage(conversationId: conversationId, initialMessage: initialMessage),
        NotesRoute(:final subjectId) => NotesPage(subjectId: subjectId),
        NoteDetailRoute(:final noteId) => NoteDetailPage(noteId: noteId),
        LiveNotesRoute() => const LiveNotesPage(),
        SubjectsRoute() => const SubjectsPage(),
        SubjectDetailRoute(:final subjectId) => SubjectDetailPage(subjectId: subjectId),
        QuizzesRoute() => const QuizzesPage(),
        QuizRunRoute(:final quizId) => QuizRunPage(quizId: quizId),
        QuizResultRoute(:final quizId, :final attemptId) =>
          QuizResultPage(quizId: quizId, attemptId: attemptId),
        FocusRoute(:final subjectId, :final assignmentId) =>
          FocusPage(subjectId: subjectId, assignmentId: assignmentId),
        TimelineRoute() => const TimelinePage(),
        MyAiRoute() => const MyAiPage(),
        PrivacyRoute() => const PrivacyPage(),
        ScreenUnderstandingRoute() => const ScreenUnderstandingPage(),
        SearchRoute(:final initialQuery) => GlobalSearchPage(initialQuery: initialQuery),
        SettingsRoute() => const AppSettingsPage(),

        // GlemtDet's pages. Not reachable from navigation any more, but still
        // built, still tested, and one sidebar entry from coming back.
        DashboardRoute() => const DashboardPage(),
        ScannerRoute() => const ScannerPage(),
        HistoryRoute() => const HistoryPage(),
        ObjectsRoute() => const ObjectsPage(),
        ObjectDetailRoute(:final objectKey) => ObjectDetailPage(objectKey: objectKey),
        ObservationDetailRoute(:final observationId) =>
          ObservationDetailPage(observationId: observationId),
      };
}

/// The page area, shared by both layouts.
class _Content extends ConsumerWidget {
  const _Content();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = ref.watch(currentRouteProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // The default layout builder stacks children with loose constraints and
      // centres them, which leaves a short page floating in the middle of the
      // window instead of sitting under the title bar. Expand instead.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.topLeft,
        children: [
          ...previousChildren,
          ?currentChild,
        ],
      ),
      child: KeyedSubtree(
        key: ValueKey(routeKey(route)),
        child: AppShell.pageFor(route),
      ),
    );
  }
}

// ------------------------------------------------------------------- wide

class _WideLayout extends ConsumerWidget {
  const _WideLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Row(
      children: [
        const _Sidebar(),
        Container(width: 1, color: colors.border),
        const Expanded(
          child: Column(
            children: [
              _TitleBar(),
              Expanded(child: _Content()),
            ],
          ),
        ),
      ],
    );
  }
}

/// A slim bar carrying the back affordance. The macOS traffic lights sit to its
/// left, so it starts indented.
class _TitleBar extends ConsumerWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationProvider.notifier);
    final canGoBack = ref.watch(navigationProvider).length > 1;
    final settings = ref.watch(settingsProvider);

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 12),
          if (canGoBack)
            _GlyphButton(icon: AppIcons.back, tooltip: 'Tilbage', onTap: nav.pop, size: 22)
          else
            const SizedBox(width: 8),
          const Spacer(),
          if (settings.screenUnderstandingEnabled) const _ScreenActiveBadge(),
          _GlyphButton(
            icon: AppIcons.search,
            tooltip: 'Søg',
            onTap: () => nav.go(const SearchRoute()),
          ),
          _GlyphButton(
            icon: AppIcons.settings,
            tooltip: 'Indstillinger',
            onTap: () => nav.go(const SettingsRoute()),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// Always visible while the screen is being read. It cannot be dismissed.
class _ScreenActiveBadge extends ConsumerWidget {
  const _ScreenActiveBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Tooltip(
      message: 'TeenBrain kan læse din skærm. Slå det fra under Privatliv.',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => ref.read(navigationProvider.notifier).go(const PrivacyRoute()),
          child: Container(
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: colors.recording.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: colors.recording, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  'Skærm',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: colors.recording,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 17,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Icon(icon, size: size, color: colors.textSecondary),
        ),
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final section = sectionOf(ref.watch(currentRouteProvider));
    final nav = ref.watch(navigationProvider.notifier);
    final profile = ref.watch(profileProvider).value;

    return Container(
      width: 216,
      color: colors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 44),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 18),
            child: GestureDetector(
              onTap: () => nav.go(const HomeRoute()),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  'TeenBrain',
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontSize: 16,
                        letterSpacing: -0.3,
                      ),
                ),
              ),
            ),
          ),
          for (final destination in _destinations)
            _SidebarItem(
              icon: destination.icon,
              label: destination.label,
              selected: section == destination.section,
              onTap: () => nav.go(destination.route),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Container(height: 1, color: colors.border),
          ),
          _SidebarItem(
            icon: AppIcons.privacy,
            label: 'Privatliv',
            selected: ref.watch(currentRouteProvider) is PrivacyRoute,
            onTap: () => nav.go(const PrivacyRoute()),
          ),
          if (profile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 14),
              child: Text(
                profile.firstName,
                style: Theme.of(context).textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.selected;
    final color = selected ? colors.textPrimary : colors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? colors.surface
                  : _hovered
                      ? colors.surfaceHover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(Insets.radiusSmall),
              border: Border.all(color: selected ? colors.border : Colors.transparent),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 17, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelLarge!.copyWith(
                          color: color,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- compact

class _CompactLayout extends ConsumerWidget {
  const _CompactLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final settings = ref.watch(settingsProvider);

    return Column(
      children: [
        SizedBox(height: MediaQuery.paddingOf(context).top),
        if (settings.screenUnderstandingEnabled)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Align(alignment: Alignment.centerRight, child: _ScreenActiveBadge()),
          ),
        const Expanded(child: _Content()),
        Container(height: 1, color: colors.border),
        const _BottomNav(),
      ],
    );
  }
}

class _BottomNav extends ConsumerWidget {
  const _BottomNav();

  /// Four destinations plus a sheet for the rest.
  static const _primary = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final section = sectionOf(ref.watch(currentRouteProvider));
    final nav = ref.watch(navigationProvider.notifier);
    final overflow = _destinations.skip(_primary).toList();
    final inOverflow = overflow.any((d) => d.section == section);

    return Container(
      color: colors.sidebar,
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      height: Insets.bottomNavHeight + MediaQuery.paddingOf(context).bottom,
      child: Row(
        children: [
          for (final destination in _destinations.take(_primary))
            Expanded(
              child: _BottomItem(
                icon: destination.icon,
                label: destination.label,
                selected: section == destination.section,
                onTap: () => nav.go(destination.route),
              ),
            ),
          Expanded(
            child: _BottomItem(
              icon: AppIcons.more,
              label: 'Mere',
              selected: inOverflow,
              onTap: () => _showMore(context, ref, overflow),
            ),
          ),
        ],
      ),
    );
  }

  void _showMore(BuildContext context, WidgetRef ref, List<_Destination> overflow) {
    final nav = ref.read(navigationProvider.notifier);
    final colors = context.colors;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Insets.radiusLarge)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            for (final destination in overflow)
              _SheetItem(
                icon: destination.icon,
                label: destination.label,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  nav.go(destination.route);
                },
              ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: colors.border,
            ),
            _SheetItem(
              icon: AppIcons.search,
              label: 'Søg',
              onTap: () {
                Navigator.of(sheetContext).pop();
                nav.go(const SearchRoute());
              },
            ),
            _SheetItem(
              icon: AppIcons.privacy,
              label: 'Privatliv',
              onTap: () {
                Navigator.of(sheetContext).pop();
                nav.go(const PrivacyRoute());
              },
            ),
            _SheetItem(
              icon: AppIcons.settings,
              label: 'Indstillinger',
              onTap: () {
                Navigator.of(sheetContext).pop();
                nav.go(const SettingsRoute());
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected ? colors.accent : colors.textTertiary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0,
                ),
          ),
        ],
      ),
    );
  }
}

class _SheetItem extends StatelessWidget {
  const _SheetItem({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Hoverable(
      onTap: onTap,
      builder: (hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        color: hovered ? colors.surfaceHover : Colors.transparent,
        child: Row(
          children: [
            Icon(icon, size: 19, color: colors.textSecondary),
            const SizedBox(width: 14),
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
