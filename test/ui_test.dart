/// Renders the real pages against a real (in-memory) database.
///
/// One thing to know before reading a failure: `flutter test` substitutes a
/// font whose every glyph is a square of the font size, so text measures far
/// wider here than it does on a real machine. That makes the phone-width
/// overflow checks below stricter than reality — which is the useful direction
/// to be wrong in, but it does mean a failure is not always a bug a user would
/// have seen.
///
/// These catch what unit tests cannot: a page that throws on an empty database,
/// a layout that overflows, a provider read before bootstrap resolves. Every
/// page is rendered twice — once with nothing in the database and once with
/// data — because "day one" and "day fifty" break in different ways.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/ai/api_key_store.dart';
import 'package:glemtdet/app/navigation.dart';
import 'package:glemtdet/app/providers.dart';
import 'package:glemtdet/app/theme.dart';
import 'package:glemtdet/data/db/local_database.dart';
import 'package:glemtdet/data/repositories/sqlite_chat_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_focus_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_memory_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_memory_store.dart';
import 'package:glemtdet/data/repositories/sqlite_note_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_profile_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_progress_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_quiz_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_school_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_search_index.dart';
import 'package:glemtdet/data/repositories/sqlite_timeline_repository.dart';
import 'package:glemtdet/data/settings_store.dart';
import 'package:glemtdet/domain/models/memory.dart';
import 'package:glemtdet/domain/models/quiz.dart';
import 'package:glemtdet/domain/models/timeline.dart';
import 'package:glemtdet/features/shell/app_shell.dart';

/// A secret store that keeps the key in memory — no Keychain under test.
class _MemorySecrets implements SecretStore {
  final Map<String, String> _values = {};

  @override
  String get description => 'testhukommelse';

  @override
  Future<String?> read(String account) async => _values[account];

  @override
  Future<void> write(String account, String value) async => _values[account] = value;

  @override
  Future<void> delete(String account) async => _values.remove(account);
}

late Directory _dir;
late LocalDatabase _db;

/// Layout errors are reported through `FlutterError.onError`, and
/// `takeException` only hands back the first one stripped of its detail. This
/// keeps the full text, so a failing test names the widget that overflowed
/// instead of just its pixel count.
final List<String> _flutterErrors = [];

void _captureErrors() {
  final previous = FlutterError.onError;
  _flutterErrors.clear();
  FlutterError.onError = (details) {
    _flutterErrors.add(details.toString());
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

/// Asserts the page drew cleanly, and says what broke when it did not.
void expectNoLayoutErrors(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception == null && _flutterErrors.isEmpty) return;
  fail([
    if (exception != null) 'Undtagelse: $exception',
    ..._flutterErrors,
  ].join('\n\n'));
}

/// Builds a fully wired app rooted at [route], against a live database.
Future<ProviderContainer> pumpRoute(
  WidgetTester tester,
  AppRoute route, {
  Size size = const Size(1280, 900),
  Future<void> Function(LocalDatabase db)? seed,
  Brightness brightness = Brightness.light,
  String? fontFamily,
}) async {
  _captureErrors();
  _dir = Directory.systemTemp.createTempSync('teenbrain_ui');
  _db = LocalDatabase.openInMemory(_dir);

  final searchIndex = SqliteSearchIndex(_db);
  await searchIndex.initialize();
  final repository = SqliteMemoryRepository(_db);
  await repository.initialize();
  final settingsStore = SettingsStore(_db);

  if (seed != null) await seed(_db);

  final bootstrap = AppBootstrap(
    database: _db,
    settingsStore: settingsStore,
    settings: settingsStore.read(),
    searchIndex: searchIndex,
    profiles: SqliteProfileRepository(_db),
    school: SqliteSchoolRepository(_db),
    notes: SqliteNoteRepository(_db, searchIndex: searchIndex),
    chats: SqliteChatRepository(_db, searchIndex: searchIndex),
    quizzes: SqliteQuizRepository(_db, searchIndex: searchIndex),
    focus: SqliteFocusRepository(_db),
    timeline: SqliteTimelineRepository(_db, searchIndex: searchIndex),
    memories: SqliteMemoryStore(_db),
    progress: SqliteProgressRepository(_db),
    repository: repository,
    apiKey: null,
  );

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    bootstrapProvider.overrideWith((ref) async => bootstrap),
    apiKeyStoreProvider.overrideWithValue(ApiKeyStore(store: _MemorySecrets())),
  ]);
  addTearDown(container.dispose);

  // The real app never builds the shell before bootstrap resolves — `_Root`
  // waits on it. Await it here for the same reason, or `requireValue` throws.
  await container.read(bootstrapProvider.future);
  container.read(navigationProvider.notifier).go(route);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: _themed(brightness, fontFamily),
        home: const AppShell(),
      ),
    ),
  );
  // Not pumpAndSettle: skeletons and the thinking indicator animate on a
  // repeating controller, so the tree is never "settled". Pumping a bounded
  // number of frames lets async loads land without waiting for a quiet tree
  // that will never come.
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  return container;
}

/// The app theme, optionally rebound to a real font so a golden looks like the
/// app rather than like a wall of squares.
ThemeData _themed(Brightness brightness, String? fontFamily) {
  final theme = buildTheme(brightness);
  if (fontFamily == null) return theme;
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: fontFamily),
  );
}

void tearDownDb() {
  _db.close();
  if (_dir.existsSync()) _dir.deleteSync(recursive: true);
}

/// Data that exercises the pages the way a real week of use would.
Future<void> seedRealistic(LocalDatabase db) async {
  final index = SqliteSearchIndex(db);
  await index.initialize();

  final profiles = SqliteProfileRepository(db);
  final school = SqliteSchoolRepository(db);
  final notes = SqliteNoteRepository(db, searchIndex: index);
  final quizzes = SqliteQuizRepository(db, searchIndex: index);
  final timeline = SqliteTimelineRepository(db, searchIndex: index);
  final memories = SqliteMemoryStore(db);
  final focus = SqliteFocusRepository(db);
  final progress = SqliteProgressRepository(db);

  final profile = await profiles.create(displayName: 'Marcus', gradeLevel: '8. klasse');
  await profiles.update(profile.copyWith(onboardedAt: DateTime.now(), xp: 420));

  final math = await school.createSubject('Matematik');
  final english = await school.createSubject('Engelsk');
  await school.createSubject('Historie');

  final equations = await school.ensureTopic(math.id, 'Ligninger');
  final quadratics = await school.ensureTopic(math.id, 'Andengradsligninger');
  await school.recordMastery(equations.id, 0.62);
  await school.recordMastery(quadratics.id, 0.18);

  await school.createAssignment(
    subjectId: math.id,
    title: 'Matematikaflevering',
    dueAt: DateTime.now().add(const Duration(days: 1)),
    estimatedMinutes: 25,
  );

  await notes.create(
    title: 'Den Franske Revolution',
    bodyMd: '## Årsager\n\n- økonomiske problemer\n- sociale forskelle\n\n'
        '## Vigtige årstal\n\n1789 — Revolutionen begynder',
    subjectId: math.id,
  );

  final quiz = await quizzes.create(
    title: 'Andengradsligninger',
    subjectId: math.id,
    topicId: quadratics.id,
    questions: const [
      QuizQuestion(
          id: 0, quizId: 0, kind: QuestionKind.multipleChoice,
          prompt: 'Hvad er diskriminanten?',
          options: ['b²-4ac', 'a²+b²', '2ab', 'b/2a'], answer: 'b²-4ac',
          explanation: 'Diskriminanten afgør antallet af løsninger.'),
      QuizQuestion(
          id: 0, quizId: 0, kind: QuestionKind.trueFalse,
          prompt: 'To løsninger når d < 0', answer: 'Falsk',
          explanation: 'Er d negativ, er der ingen reelle løsninger.'),
    ],
  );
  final attempt = await quizzes.startAttempt(quiz.id);
  await quizzes.recordAnswer(
      attemptId: attempt.id, questionId: quiz.questions[0].id,
      given: 'b²-4ac', correct: true);
  await quizzes.recordAnswer(
      attemptId: attempt.id, questionId: quiz.questions[1].id,
      given: 'Sandt', correct: false, aiFeedback: 'Det er omvendt.');
  await quizzes.finishAttempt(attempt.id);

  final session = await focus.start(subjectId: math.id);
  await focus.finish(session.id, actualSeconds: 32 * 60, completed: true);

  await timeline.record(
      kind: TimelineKind.focus, title: 'Fokus: Matematik',
      summary: '32 minutters fokus', subjectId: math.id);
  await timeline.record(
      kind: TimelineKind.quiz, title: 'Quiz: Andengradsligninger', subjectId: math.id);
  await timeline.record(
      kind: TimelineKind.study, title: 'Engelsk',
      subjectId: english.id,
      startedAt: DateTime.now().subtract(const Duration(days: 4)));

  await memories.remember(
    const MemoryCandidate(
        kind: MemoryKind.preference, key: 'explanation_style',
        value: 'Foretrækker korte forklaringer med eksempler', confidence: 1),
    source: MemorySource.onboarding,
  );
  await memories.remember(
    const MemoryCandidate(
        kind: MemoryKind.struggle, key: 'struggle.math.quadratics',
        value: 'Har svært ved fortegn i andengradsligninger', confidence: 0.8),
    source: MemorySource.quiz,
    link: const MemoryLink(refTable: 'quizzes', refId: 1),
  );
  await memories.remember(
    const MemoryCandidate(
        kind: MemoryKind.strength, key: 'strength.english',
        value: 'Er stærk til engelsk grammatik', confidence: 0.7),
    source: MemorySource.inferred,
  );

  await progress.logActivity(minutes: 32, questions: 2, xp: 32);
}

void main() {
  /// Every route that has a page, and whether it needs an id from the seed.
  final routes = <String, AppRoute>{
    'forside': const HomeRoute(),
    'chat': const ChatRoute(),
    'noter': const NotesRoute(),
    'live notes': const LiveNotesRoute(),
    'fag': const SubjectsRoute(),
    'quiz': const QuizzesRoute(),
    'fokus': const FocusRoute(),
    'timeline': const TimelineRoute(),
    'min ai': const MyAiRoute(),
    'søgning': const SearchRoute(),
    'privatliv': const PrivacyRoute(),
    'skærmforståelse': const ScreenUnderstandingRoute(),
    'indstillinger': const SettingsRoute(),
  };

  group('hver side tegner på en tom database', () {
    for (final entry in routes.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpRoute(tester, entry.value);
        expectNoLayoutErrors(tester);
        tearDownDb();
      });
    }
  });

  group('hver side tegner med rigtige data', () {
    for (final entry in routes.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpRoute(tester, entry.value, seed: seedRealistic);
        expectNoLayoutErrors(tester);
        tearDownDb();
      });
    }
  });

  group('hver side tegner på en telefon uden at flyde over', () {
    for (final entry in routes.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpRoute(
          tester,
          entry.value,
          size: const Size(390, 844),
          seed: seedRealistic,
        );
        expectNoLayoutErrors(tester);
        tearDownDb();
      });
    }
  });

  group('detaljesider', () {
    testWidgets('noten kan åbnes', (tester) async {
      await pumpRoute(tester, const NoteDetailRoute(1), seed: seedRealistic);
      expect(find.text('Den Franske Revolution'), findsWidgets);
      expectNoLayoutErrors(tester);
      tearDownDb();
    });

    testWidgets('faget kan åbnes', (tester) async {
      await pumpRoute(tester, const SubjectDetailRoute(1), seed: seedRealistic);
      expect(find.text('Matematik'), findsWidgets);
      expect(find.text('Andengradsligninger'), findsWidgets);
      expectNoLayoutErrors(tester);
      tearDownDb();
    });

    testWidgets('quizresultatet viser scoren og fejlen', (tester) async {
      await pumpRoute(
        tester,
        const QuizResultRoute(quizId: 1, attemptId: 1),
        seed: seedRealistic,
      );
      expect(find.text('Du scorede 1/2'), findsOneWidget);
      expect(find.text('Det er omvendt.'), findsOneWidget);
      expectNoLayoutErrors(tester);
      tearDownDb();
    });

    testWidgets('en note der ikke findes tegner stadig', (tester) async {
      await pumpRoute(tester, const NoteDetailRoute(999));
      expectNoLayoutErrors(tester);
      tearDownDb();
    });

    testWidgets('en quiz der ikke findes tegner stadig', (tester) async {
      await pumpRoute(tester, const QuizRunRoute(999));
      expectNoLayoutErrors(tester);
      tearDownDb();
    });
  });

  group('layoutet skifter med bredden', () {
    testWidgets('sidebar på en stor skærm', (tester) async {
      await pumpRoute(tester, const HomeRoute(), size: const Size(1280, 900));
      expect(find.text('TeenBrain'), findsWidgets);
      // Sidebar-punkter, som bundlinjen ikke har plads til.
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Min AI'), findsOneWidget);
      expect(find.text('Mere'), findsNothing);
      tearDownDb();
    });

    testWidgets('bundnavigation på en telefon', (tester) async {
      await pumpRoute(tester, const HomeRoute(), size: const Size(390, 844));
      expect(find.text('Mere'), findsOneWidget);
      // Timeline flytter ind i "Mere"-arket.
      expect(find.text('Timeline'), findsNothing);
      tearDownDb();
    });
  });

  group('forsiden', () {
    testWidgets('hilser med fornavnet', (tester) async {
      await pumpRoute(tester, const HomeRoute(), seed: seedRealistic);
      expect(find.textContaining('Marcus'), findsWidgets);
      expect(find.text('Hvad skal vi fokusere på?'), findsOneWidget);
      expect(find.text('Hvad kan jeg hjælpe dig med?'), findsOneWidget);
      tearDownDb();
    });

    testWidgets('deadline vises som "I morgen"', (tester) async {
      await pumpRoute(tester, const HomeRoute(), seed: seedRealistic);
      expect(find.text('Matematikaflevering'), findsOneWidget);
      expect(find.text('I morgen'), findsOneWidget);
      tearDownDb();
    });

    testWidgets('uden nøgle siger forslagene hvorfor', (tester) async {
      await pumpRoute(tester, const HomeRoute(), seed: seedRealistic);
      expect(find.text('Forslag kræver en API-nøgle'), findsOneWidget);
      tearDownDb();
    });
  });

  group('min ai', () {
    testWidgets('viser hukommelsen grupperet med kilde', (tester) async {
      await pumpRoute(tester, const MyAiRoute(), seed: seedRealistic);
      // SectionHeading renders its text in caps.
      expect(find.text('SÅDAN LÆRER DU BEDST'), findsOneWidget);
      expect(find.text('DET DU HAR SVÆRT VED'), findsOneWidget);
      expect(find.text('Du fortalte mig det'), findsWidgets);
      expect(find.text('Målt i en quiz'), findsWidgets);
      tearDownDb();
    });
  });

  group('privatliv', () {
    testWidgets('siger hvad der ikke forlader maskinen', (tester) async {
      await pumpRoute(tester, const PrivacyRoute(), seed: seedRealistic);
      expect(find.text('Hvad forlader din computer'), findsOneWidget);
      expect(find.text('Sendes aldrig'), findsOneWidget);
      tearDownDb();
    });

    testWidgets('alt der observerer er slået fra som standard', (tester) async {
      final container = await pumpRoute(tester, const PrivacyRoute());
      final settings = container.read(settingsProvider);
      expect(settings.screenUnderstandingEnabled, isFalse);
      expect(settings.microphoneEnabled, isFalse);
      expect(settings.automaticNotesEnabled, isFalse);
      expect(settings.aiMemoryEnabled, isTrue);
      tearDownDb();
    });
  });

  group('ingen døde knapper', () {
    testWidgets('ting der ikke er bygget er markeret, ikke skjult', (tester) async {
      await pumpRoute(tester, const ScreenUnderstandingRoute());
      expect(find.text('Kommer snart'), findsWidgets);
      expect(find.text('Funktionen er ikke bygget endnu'), findsOneWidget);
      tearDownDb();
    });

    testWidgets('Live Notes optager ikke med mikrofonen slået fra', (tester) async {
      // Mikrofonen er slået fra som standard, så siden skal tilbyde kontakten
      // i stedet for en optageknap, der ville fejle.
      await pumpRoute(tester, const LiveNotesRoute());
      expect(find.text('Mikrofonen er slået fra'), findsOneWidget);
      expect(find.text('Slå mikrofonen til'), findsOneWidget);
      expect(find.text('OPTAGER'), findsNothing);
      expectNoLayoutErrors(tester);
      tearDownDb();
    });

    testWidgets('optageknappen dukker op, når mikrofonen er slået til',
        (tester) async {
      final container = await pumpRoute(tester, const LiveNotesRoute());
      container.read(settingsProvider.notifier).setMicrophone(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text('Klar til at optage'), findsOneWidget);
      expect(find.text('Mikrofonen er slået fra'), findsNothing);
      expectNoLayoutErrors(tester);
      tearDownDb();
    });
  });
}
