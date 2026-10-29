/// Navigation is a small explicit state machine rather than a URL router:
/// TeenBrain is a handful of pages, and a stack of typed destinations is easier
/// to reason about — and exhaustively switch over — than string paths.
///
/// GlemtDet's destinations are kept below. They are not in the sidebar any
/// more, but the pages still build and their tests still pass, so restoring the
/// visual-memory feature is a matter of adding sidebar entries back.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class AppRoute {
  const AppRoute();
}

// ---- TeenBrain -------------------------------------------------------------

class HomeRoute extends AppRoute {
  const HomeRoute();
}

class ChatRoute extends AppRoute {
  const ChatRoute({this.conversationId, this.initialMessage});

  /// Null starts a new conversation.
  final int? conversationId;

  /// Sent as soon as the page opens — how the dashboard's input box hands off.
  final String? initialMessage;
}

class NotesRoute extends AppRoute {
  const NotesRoute({this.subjectId});
  final int? subjectId;
}

class NoteDetailRoute extends AppRoute {
  const NoteDetailRoute(this.noteId);
  final int noteId;
}

class LiveNotesRoute extends AppRoute {
  const LiveNotesRoute();
}

class SubjectsRoute extends AppRoute {
  const SubjectsRoute();
}

class SubjectDetailRoute extends AppRoute {
  const SubjectDetailRoute(this.subjectId);
  final int subjectId;
}

class QuizzesRoute extends AppRoute {
  const QuizzesRoute();
}

class QuizRunRoute extends AppRoute {
  const QuizRunRoute(this.quizId);
  final int quizId;
}

class QuizResultRoute extends AppRoute {
  const QuizResultRoute({required this.quizId, required this.attemptId});
  final int quizId;
  final int attemptId;
}

class FocusRoute extends AppRoute {
  const FocusRoute({this.subjectId, this.assignmentId});
  final int? subjectId;
  final int? assignmentId;
}

class TimelineRoute extends AppRoute {
  const TimelineRoute();
}

class MyAiRoute extends AppRoute {
  const MyAiRoute();
}

class PrivacyRoute extends AppRoute {
  const PrivacyRoute();
}

class ScreenUnderstandingRoute extends AppRoute {
  const ScreenUnderstandingRoute();
}

// ---- Shared ----------------------------------------------------------------

class SearchRoute extends AppRoute {
  const SearchRoute({this.initialQuery});
  final String? initialQuery;
}

class SettingsRoute extends AppRoute {
  const SettingsRoute();
}

// ---- GlemtDet (kept, not in the navigation) --------------------------------

class DashboardRoute extends AppRoute {
  const DashboardRoute();
}

class ScannerRoute extends AppRoute {
  const ScannerRoute();
}

class HistoryRoute extends AppRoute {
  const HistoryRoute();
}

class ObjectsRoute extends AppRoute {
  const ObjectsRoute();
}

class ObjectDetailRoute extends AppRoute {
  const ObjectDetailRoute(this.objectKey);
  final String objectKey;
}

class ObservationDetailRoute extends AppRoute {
  const ObservationDetailRoute(this.observationId);
  final int observationId;
}

// ---- Sections --------------------------------------------------------------

/// Which navigation entry should look selected for a given route.
enum SidebarSection { home, chat, notes, subjects, quizzes, timeline, myAi, settings, legacy }

SidebarSection sectionOf(AppRoute route) => switch (route) {
      HomeRoute() => SidebarSection.home,
      ChatRoute() => SidebarSection.chat,
      NotesRoute() || NoteDetailRoute() || LiveNotesRoute() => SidebarSection.notes,
      SubjectsRoute() || SubjectDetailRoute() || FocusRoute() => SidebarSection.subjects,
      QuizzesRoute() || QuizRunRoute() || QuizResultRoute() => SidebarSection.quizzes,
      TimelineRoute() || SearchRoute() => SidebarSection.timeline,
      MyAiRoute() => SidebarSection.myAi,
      SettingsRoute() || PrivacyRoute() || ScreenUnderstandingRoute() =>
        SidebarSection.settings,
      DashboardRoute() ||
      ScannerRoute() ||
      HistoryRoute() ||
      ObjectsRoute() ||
      ObjectDetailRoute() ||
      ObservationDetailRoute() =>
        SidebarSection.legacy,
    };

/// A stable key per destination, so the page switcher animates on real changes
/// and not on every rebuild.
String routeKey(AppRoute route) => switch (route) {
      HomeRoute() => 'home',
      ChatRoute(:final conversationId) => 'chat:$conversationId',
      NotesRoute(:final subjectId) => 'notes:$subjectId',
      NoteDetailRoute(:final noteId) => 'note:$noteId',
      LiveNotesRoute() => 'live-notes',
      SubjectsRoute() => 'subjects',
      SubjectDetailRoute(:final subjectId) => 'subject:$subjectId',
      QuizzesRoute() => 'quizzes',
      QuizRunRoute(:final quizId) => 'quiz:$quizId',
      QuizResultRoute(:final attemptId) => 'quiz-result:$attemptId',
      FocusRoute(:final subjectId, :final assignmentId) => 'focus:$subjectId:$assignmentId',
      TimelineRoute() => 'timeline',
      MyAiRoute() => 'my-ai',
      PrivacyRoute() => 'privacy',
      ScreenUnderstandingRoute() => 'screen',
      SearchRoute(:final initialQuery) => 'search:$initialQuery',
      SettingsRoute() => 'settings',
      DashboardRoute() => 'gd-dashboard',
      ScannerRoute() => 'gd-scanner',
      HistoryRoute() => 'gd-history',
      ObjectsRoute() => 'gd-objects',
      ObjectDetailRoute(:final objectKey) => 'gd-object:$objectKey',
      ObservationDetailRoute(:final observationId) => 'gd-obs:$observationId',
    };

class NavigationController extends Notifier<List<AppRoute>> {
  @override
  List<AppRoute> build() => const [HomeRoute()];

  AppRoute get current => state.last;
  bool get canGoBack => state.length > 1;

  /// Replaces the stack — used by the sidebar and bottom bar, where there is
  /// no "back".
  void go(AppRoute route) => state = [route];

  /// Pushes a detail view on top of the current page.
  void push(AppRoute route) => state = [...state, route];

  void pop() {
    if (state.length > 1) state = state.sublist(0, state.length - 1);
  }

  /// Returns to the root of the current stack.
  void popToRoot() {
    if (state.length > 1) state = [state.first];
  }
}

final navigationProvider =
    NotifierProvider<NavigationController, List<AppRoute>>(NavigationController.new);

final currentRouteProvider = Provider<AppRoute>((ref) => ref.watch(navigationProvider).last);
