import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/data/db/local_database.dart';
import 'package:glemtdet/data/repositories/sqlite_chat_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_focus_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_memory_store.dart';
import 'package:glemtdet/data/repositories/sqlite_note_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_profile_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_progress_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_quiz_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_school_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_search_index.dart';
import 'package:glemtdet/data/repositories/sqlite_timeline_repository.dart';
import 'package:glemtdet/domain/models/chat.dart';
import 'package:glemtdet/domain/models/memory.dart';
import 'package:glemtdet/domain/models/profile.dart';
import 'package:glemtdet/domain/models/quiz.dart';
import 'package:glemtdet/domain/models/school.dart';
import 'package:glemtdet/domain/models/search.dart';
import 'package:glemtdet/domain/models/timeline.dart';

void main() {
  late Directory dir;
  late LocalDatabase db;
  late SqliteSearchIndex search;
  late SqliteProfileRepository profiles;
  late SqliteSchoolRepository school;
  late SqliteNoteRepository notes;
  late SqliteChatRepository chats;
  late SqliteQuizRepository quizzes;
  late SqliteFocusRepository focus;
  late SqliteTimelineRepository timeline;
  late SqliteMemoryStore memories;
  late SqliteProgressRepository progress;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('teenbrain_test');
    db = LocalDatabase.openInMemory(dir);
    search = SqliteSearchIndex(db);
    await search.initialize();
    profiles = SqliteProfileRepository(db);
    school = SqliteSchoolRepository(db);
    notes = SqliteNoteRepository(db, searchIndex: search);
    chats = SqliteChatRepository(db, searchIndex: search);
    quizzes = SqliteQuizRepository(db, searchIndex: search);
    focus = SqliteFocusRepository(db);
    timeline = SqliteTimelineRepository(db, searchIndex: search);
    memories = SqliteMemoryStore(db);
    progress = SqliteProgressRepository(db);
  });

  tearDown(() {
    db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('migration', () {
    test('v2 sidder ovenpå v1 uden at røre GlemtDets tabeller', () {
      final tables = db.db
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((r) => r['name'] as String)
          .toSet();

      // v1 skal stadig være der
      expect(tables, containsAll(['objects', 'places', 'observations', 'settings']));
      // v2 skal være kommet til
      expect(tables, containsAll(['profile', 'subjects', 'notes', 'memories', 'search_map']));
    });
  });

  group('profil', () {
    test('findes ikke før onboarding', () async {
      expect(await profiles.read(), isNull);
    });

    test('oprettes og henter fornavn ud', () async {
      final p = await profiles.create(displayName: 'Marcus Grevsen', gradeLevel: '8. klasse');
      expect(p.firstName, 'Marcus');
      expect(p.isOnboarded, isFalse);
      expect((await profiles.read())!.gradeLevel, '8. klasse');
    });

    test('XP kan ikke gå i minus', () async {
      await profiles.create(displayName: 'Marcus');
      await profiles.addXp(50);
      final p = await profiles.addXp(-200);
      expect(p.xp, 0);
    });

    test('level-kurven starter blødt og bliver stejlere', () {
      expect(Level.forXp(0).number, 1);
      expect(Level.forXp(100).number, 2);
      expect(Level.forXp(299).number, 2);
      expect(Level.forXp(300).number, 3);
      expect(Level.forXp(150).xpIntoLevel, 50);
      expect(Level.forXp(150).xpForLevel, 200);
    });
  });

  group('fag og emner', () {
    test('samme fagnavn opretter ikke to rækker', () async {
      final a = await school.createSubject('Matematik');
      final b = await school.createSubject('matematik');
      expect(a.id, b.id);
    });

    test('fag findes på navn på tværs af store bogstaver og æøå', () async {
      await school.createSubject('Fysik/kemi');
      expect((await school.subjectByName('FYSIK/KEMI'))!.name, 'Fysik/kemi');
      await school.createSubject('Håndværk');
      expect(await school.subjectByName('haandvaerk'), isNotNull);
    });

    test('fag får hver sin farve fra paletten', () async {
      final colors = <String>{};
      for (final name in ['Matematik', 'Dansk', 'Engelsk', 'Fysik', 'Historie', 'Biologi']) {
        colors.add((await school.createSubject(name)).colorToken);
      }
      expect(colors.length, 6);
    });

    test('ensureTopic er idempotent', () async {
      final s = await school.createSubject('Matematik');
      final a = await school.ensureTopic(s.id, 'Ligninger');
      final b = await school.ensureTopic(s.id, 'ligninger');
      expect(a.id, b.id);
    });

    test('mastery glider i stedet for at springe', () async {
      final s = await school.createSubject('Matematik');
      final t = await school.ensureTopic(s.id, 'Brøker');

      // Første måling sætter niveauet — der er intet at glide fra.
      var updated = await school.recordMastery(t.id, 0.9);
      expect(updated.mastery, closeTo(0.9, 0.001));

      // En enkelt dårlig quiz må ikke slette et semesters arbejde.
      updated = await school.recordMastery(t.id, 0.0);
      expect(updated.mastery, greaterThan(0.5));
      expect(updated.mastery, lessThan(0.9));
    });

    test('emner falder i de tre bånd', () async {
      final s = await school.createSubject('Matematik');
      final weak = await school.ensureTopic(s.id, 'Andengradsligninger');
      final strong = await school.ensureTopic(s.id, 'Procent');
      await school.recordMastery(weak.id, 0.1);
      await school.recordMastery(strong.id, 0.9);

      final topics = await school.topics(s.id);
      final bands = {for (final t in topics) t.name: t.band};
      expect(bands['Andengradsligninger'], MasteryBand.needsWork);
      expect(bands['Procent'], MasteryBand.strong);
    });

    test('kommende opgaver er sorteret efter deadline og udelader færdige', () async {
      final s = await school.createSubject('Matematik');
      final now = DateTime.now();
      await school.createAssignment(
          subjectId: s.id, title: 'Om tre dage', dueAt: now.add(const Duration(days: 3)));
      final soon = await school.createAssignment(
          subjectId: s.id, title: 'I morgen', dueAt: now.add(const Duration(days: 1)));
      final done = await school.createAssignment(
          subjectId: s.id, title: 'Færdig', dueAt: now.add(const Duration(hours: 2)));
      await school.setAssignmentDone(done.id, true);

      final upcoming = await school.upcoming();
      expect(upcoming.first.id, soon.id);
      expect(upcoming.map((a) => a.title), isNot(contains('Færdig')));
    });

    test('opgave ved hvor mange dage der er til deadline', () async {
      final now = DateTime(2026, 9, 4, 23, 30);
      final a = Assignment(
        id: 1,
        title: 'Matematikaflevering',
        dueAt: DateTime(2026, 9, 5, 8, 0),
        createdAt: now,
      );
      // Otte en halv time senere, men "i morgen" — dage, ikke timer.
      expect(a.daysUntilDue(now), 1);
      expect(a.isOverdue(now), isFalse);
      expect(a.isOverdue(DateTime(2026, 9, 6)), isTrue);
    });

    test('opsummering samler tal fra fire tabeller', () async {
      final s = await school.createSubject('Matematik');
      await school.ensureTopic(s.id, 'Ligninger');
      await school.createAssignment(subjectId: s.id, title: 'Aflevering');

      final session = await focus.start(subjectId: s.id);
      await focus.finish(session.id, actualSeconds: 45 * 60, completed: true);
      await timeline.record(kind: TimelineKind.study, title: 'Matematik', subjectId: s.id);

      final quiz = await quizzes.create(
        title: 'Ligninger',
        subjectId: s.id,
        questions: const [
          QuizQuestion(id: 0, quizId: 0, kind: QuestionKind.trueFalse, prompt: 'a', answer: 'sandt'),
          QuizQuestion(id: 0, quizId: 0, kind: QuestionKind.trueFalse, prompt: 'b', answer: 'falsk'),
        ],
      );
      final attempt = await quizzes.startAttempt(quiz.id);
      await quizzes.recordAnswer(
          attemptId: attempt.id, questionId: quiz.questions[0].id, given: 'sandt', correct: true);
      await quizzes.recordAnswer(
          attemptId: attempt.id, questionId: quiz.questions[1].id, given: 'sandt', correct: false);

      final summary = (await school.summary(s.id))!;
      expect(summary.minutesLast7Days, 45);
      expect(summary.openAssignments, hasLength(1));
      expect(summary.questionsAnswered, 2);
      expect(summary.questionsCorrect, 1);
      expect(summary.accuracy, closeTo(0.5, 0.001));
      expect(summary.lastStudied, isNotNull);
    });
  });

  group('noter', () {
    test('preview springer overskrifter over', () async {
      final n = await notes.create(
        title: 'Den Franske Revolution',
        bodyMd: '# Årsager\n\n- økonomiske problemer\n- sociale forskelle',
      );
      expect(n.preview, 'økonomiske problemer');
      expect(n.wordCount, greaterThan(3));
    });

    test('fastgjorte noter kommer først', () async {
      await notes.create(title: 'Gammel');
      final pinned = await notes.create(title: 'Vigtig');
      await notes.setPinned(pinned.id, true);
      expect((await notes.notes()).first.title, 'Vigtig');
    });

    test('korpus respekterer sit tegnbudget', () async {
      for (var i = 0; i < 30; i++) {
        await notes.create(title: 'Note $i', bodyMd: 'x' * 500);
      }
      final corpus = await notes.corpusFor(maxChars: 2000);
      expect(corpus.length, lessThanOrEqualTo(2000));
      expect(corpus, isNotEmpty);
    });
  });

  group('quiz', () {
    Future<Quiz> makeQuiz() => quizzes.create(
          title: 'Brøker',
          questions: const [
            QuizQuestion(
                id: 0, quizId: 0, kind: QuestionKind.multipleChoice,
                prompt: 'Hvad er 1/2 + 1/4?', options: ['3/4', '2/6'], answer: '3/4'),
            QuizQuestion(
                id: 0, quizId: 0, kind: QuestionKind.shortAnswer,
                prompt: 'Forkort 4/8', answer: '1/2'),
          ],
        );

    test('en quiz uden spørgsmål kan ikke gemmes', () {
      expect(
        () => quizzes.create(title: 'Tom', questions: const []),
        throwsArgumentError,
      );
    });

    test('spørgsmål og svarmuligheder overlever en rundtur', () async {
      final quiz = (await quizzes.quiz((await makeQuiz()).id))!;
      expect(quiz.questions, hasLength(2));
      expect(quiz.questions.first.options, ['3/4', '2/6']);
      expect(quiz.questions.first.kind, QuestionKind.multipleChoice);
    });

    test('at svare igen retter scoren i stedet for at tælle dobbelt', () async {
      final quiz = await makeQuiz();
      final attempt = await quizzes.startAttempt(quiz.id);
      final q = quiz.questions.first.id;

      await quizzes.recordAnswer(attemptId: attempt.id, questionId: q, given: '2/6', correct: false);
      await quizzes.recordAnswer(attemptId: attempt.id, questionId: q, given: '3/4', correct: true);

      final finished = await quizzes.finishAttempt(attempt.id);
      expect(finished.score, 1);
      expect(finished.total, 2);
      expect(finished.answers, hasLength(1));
      expect(finished.scoreLine, '1/2');
    });

    test('fejl kan hentes frem igen til en ny quiz', () async {
      final quiz = await makeQuiz();
      final attempt = await quizzes.startAttempt(quiz.id);
      await quizzes.recordAnswer(
          attemptId: attempt.id, questionId: quiz.questions[1].id, given: '2/4', correct: false);

      final mistakes = await quizzes.recentMistakes();
      expect(mistakes, hasLength(1));
      expect(mistakes.first.prompt, 'Forkort 4/8');
    });
  });

  group('fokus', () {
    test('kun én session kan være åben ad gangen', () async {
      final first = await focus.start(plannedMinutes: 25);
      await focus.start(plannedMinutes: 25);

      final closed = await focus.session(first.id);
      expect(closed!.isRunning, isFalse);
      expect(closed.completed, isFalse);
      expect(await focus.openSession(), isNotNull);
    });

    test('korte sessioner rapporteres i sekunder', () async {
      final s = await focus.start();
      final done = await focus.finish(s.id, actualSeconds: 40, completed: false);
      expect(done.durationLine, '40 sekunders fokus');

      final s2 = await focus.start();
      final done2 = await focus.finish(s2.id, actualSeconds: 32 * 60, completed: true);
      expect(done2.durationLine, '32 minutters fokus');
    });
  });

  group('timeline', () {
    test('grupperer efter kalenderdag, nyeste først', () async {
      final now = DateTime.now();
      await timeline.record(
          kind: TimelineKind.study, title: 'I går', startedAt: now.subtract(const Duration(days: 1)));
      await timeline.record(kind: TimelineKind.quiz, title: 'I dag kl. 13', startedAt: now);
      await timeline.record(
          kind: TimelineKind.note, title: 'I dag kl. 15',
          startedAt: now.add(const Duration(minutes: 1)));

      final days = await timeline.days();
      expect(days, hasLength(2));
      expect(days.first.events, hasLength(2));
      expect(days.first.events.first.title, 'I dag kl. 15');
    });

    test('ved hvornår hvert fag sidst blev rørt', () async {
      final s = await school.createSubject('Engelsk');
      final fourDaysAgo = DateTime.now().subtract(const Duration(days: 4));
      await timeline.record(
          kind: TimelineKind.study, title: 'Engelsk', subjectId: s.id, startedAt: fourDaysAgo);

      final touched = await timeline.lastTouchedPerSubject();
      expect(DateTime.now().difference(touched[s.id]!).inDays, 4);
    });

    test('fagnavnet hentes med i samme forespørgsel', () async {
      final s = await school.createSubject('Historie');
      final e = await timeline.record(
          kind: TimelineKind.study, title: 'Den franske revolution', subjectId: s.id);
      expect((await timeline.event(e.id))!.subjectName, 'Historie');
    });
  });

  group('hukommelse', () {
    test('samme nøgle opdaterer i stedet for at hobe sig op', () async {
      await memories.remember(
        const MemoryCandidate(
            kind: MemoryKind.fact, key: 'grade_level', value: '7. klasse'),
        source: MemorySource.onboarding,
      );
      await memories.remember(
        const MemoryCandidate(
            kind: MemoryKind.fact, key: 'grade_level', value: '8. klasse'),
        source: MemorySource.userEdit,
      );

      final all = await memories.all(kind: MemoryKind.fact);
      expect(all, hasLength(1));
      expect(all.first.value, '8. klasse');
    });

    test('modellen overskriver ikke noget brugeren selv har sagt', () async {
      await memories.remember(
        const MemoryCandidate(
            kind: MemoryKind.preference, key: 'style', value: 'Korte forklaringer'),
        source: MemorySource.onboarding,
      );
      await memories.remember(
        const MemoryCandidate(
            kind: MemoryKind.preference, key: 'style', value: 'Lange essays', confidence: 0.9),
        source: MemorySource.inferred,
      );

      final memory = (await memories.byKey(MemoryKind.preference, 'style'))!;
      expect(memory.value, 'Korte forklaringer');
      expect(memory.source, MemorySource.onboarding);
    });

    test('tillid vokser ved gentagelse, men når aldrig 100 %', () async {
      for (var i = 0; i < 25; i++) {
        await memories.remember(
          const MemoryCandidate(
              kind: MemoryKind.struggle, key: 'math.quadratics',
              value: 'Andengradsligninger', confidence: 0.8),
          source: MemorySource.quiz,
        );
      }
      final memory = (await memories.byKey(MemoryKind.struggle, 'math.quadratics'))!;
      expect(memory.confidence, greaterThan(0.8));
      expect(memory.confidence, lessThan(1.0));
    });

    test('en deaktiveret memory beholder sin række men falder ud af rangeringen', () async {
      final m = await memories.remember(
        const MemoryCandidate(kind: MemoryKind.fact, key: 'school', value: 'Vestre Skole'),
        source: MemorySource.onboarding,
      );
      await memories.setActive(m.id, false);

      expect(await memories.all(), hasLength(1));
      expect(await memories.ranked(terms: const ['skole']), isEmpty);
      expect(await memories.count(activeOnly: true), 0);
    });

    test('rangering finder det relevante frem for det nyeste', () async {
      await memories.remember(
        const MemoryCandidate(
            kind: MemoryKind.learning, key: 'topic.photosynthesis',
            value: 'Arbejdede med fotosyntese i biologi'),
        source: MemorySource.session,
      );
      await memories.remember(
        const MemoryCandidate(
            kind: MemoryKind.learning, key: 'topic.rome', value: 'Læste om Romerriget'),
        source: MemorySource.session,
      );

      final ranked = await memories.ranked(terms: const ['fotosyntese']);
      expect(ranked.first.key, 'topic.photosynthesis');
    });

    test('fastgjort hukommelse ligger altid øverst', () async {
      final pinned = await memories.remember(
        const MemoryCandidate(kind: MemoryKind.learning, key: 'x', value: 'Ligegyldig detalje'),
        source: MemorySource.inferred,
      );
      await memories.setPinned(pinned.id, true);
      await memories.remember(
        const MemoryCandidate(
            kind: MemoryKind.preference, key: 'style', value: 'Korte forklaringer'),
        source: MemorySource.onboarding,
      );

      expect((await memories.ranked(terms: const ['forklaring'])).first.id, pinned.id);
    });

    test('oprindelsen kan spores tilbage', () async {
      final m = await memories.remember(
        const MemoryCandidate(kind: MemoryKind.struggle, key: 'k', value: 'v'),
        source: MemorySource.quiz,
        link: const MemoryLink(refTable: 'quizzes', refId: 7),
      );
      final links = await memories.linksFor(m.id);
      expect(links.single.refTable, 'quizzes');
      expect(links.single.refId, 7);
    });

    test('brug tælles og påvirker fremtidig rangering', () async {
      final m = await memories.remember(
        const MemoryCandidate(kind: MemoryKind.learning, key: 'k', value: 'v'),
        source: MemorySource.inferred,
      );
      await memories.markUsed([m.id]);
      await memories.markUsed([m.id]);
      expect((await memories.byId(m.id))!.useCount, 2);
    });
  });

  group('søgning', () {
    test('FTS5 er tilgængelig i den bundtede SQLite', () {
      // Fejler den her, falder søgningen tilbage på LIKE — testene under
      // dækker begge veje, men det er værd at vide hvilken der er i brug.
      expect(search.hasFullTextSearch, isTrue);
    });

    test('finder en note på et ord inde i teksten', () async {
      await notes.create(
        title: 'Biologi',
        bodyMd: 'Fotosyntese er den proces hvor planter omdanner lys til energi.',
      );
      final hits = await search.query(const SearchInterpretation.plain(['fotosyntese']));
      expect(hits, isNotEmpty);
      expect(hits.first.scope, SearchScope.note);
      expect(hits.first.snippet, contains('planter'));
    });

    test('titel-match slår krop-match', () async {
      await notes.create(title: 'Anden verdenskrig', bodyMd: 'Noget om noget andet.');
      await notes.create(title: 'Løst og fast', bodyMd: 'En sætning der nævner verdenskrig én gang.');

      final hits = await search.query(const SearchInterpretation.plain(['verdenskrig']));
      expect(hits.first.title, 'Anden verdenskrig');
    });

    test('søger på tværs af noter, samtaler og quizzer', () async {
      await notes.create(title: 'Fotosyntese', bodyMd: 'planter');
      final c = await chats.createConversation(title: 'Om fotosyntese');
      await chats.addMessage(
          conversationId: c.id, role: ChatRole.user, content: 'Forklar fotosyntese');
      await quizzes.create(
        title: 'Fotosyntese-quiz',
        questions: const [
          QuizQuestion(
              id: 0, quizId: 0, kind: QuestionKind.trueFalse,
              prompt: 'Planter bruger lys', answer: 'sandt'),
        ],
      );

      final hits = await search.query(const SearchInterpretation.plain(['fotosyntese']));
      expect(hits.map((h) => h.scope).toSet(),
          containsAll([SearchScope.note, SearchScope.conversation, SearchScope.quiz]));
    });

    test('en slettet note forsvinder fra indekset', () async {
      final n = await notes.create(title: 'Midlertidig', bodyMd: 'fotosyntese');
      expect(await search.query(const SearchInterpretation.plain(['midlertidig'])), isNotEmpty);
      await notes.delete(n.id);
      expect(await search.query(const SearchInterpretation.plain(['midlertidig'])), isEmpty);
    });

    test('en redigeret note indekseres på sin nye tekst, ikke sin gamle', () async {
      final n = await notes.create(title: 'Første titel', bodyMd: 'oprindelig tekst');
      await notes.update(n.copyWith(title: 'Ny titel', bodyMd: 'ændret tekst'));

      expect(await search.query(const SearchInterpretation.plain(['oprindelig'])), isEmpty);
      expect(await search.query(const SearchInterpretation.plain(['ændret'])), isNotEmpty);
    });

    test('tidsvindue afgrænser resultatet', () async {
      final old = DateTime.now().subtract(const Duration(days: 60));
      await timeline.record(kind: TimelineKind.study, title: 'Gammel fotosyntese', startedAt: old);
      await timeline.record(kind: TimelineKind.study, title: 'Ny fotosyntese');

      final recent = await search.query(SearchInterpretation(
        terms: const ['fotosyntese'],
        after: DateTime.now().subtract(const Duration(days: 7)),
      ));
      expect(recent, hasLength(1));
      expect(recent.first.title, 'Ny fotosyntese');
    });

    test('genopbygning giver samme indeks som løbende skrivning', () async {
      await notes.create(title: 'Fotosyntese', bodyMd: 'planter og lys');
      await timeline.record(kind: TimelineKind.study, title: 'Biologi');

      final before = await search.query(const SearchInterpretation.plain(['fotosyntese']));
      final count = await search.rebuild();
      final after = await search.query(const SearchInterpretation.plain(['fotosyntese']));

      expect(count, greaterThanOrEqualTo(2));
      expect(after.map((h) => h.refId), before.map((h) => h.refId));
    });

    test('æøå kan søges uden æøå', () async {
      await notes.create(title: 'Brøker og målestok', bodyMd: 'Om størrelser.');
      expect(await search.query(const SearchInterpretation.plain(['broker'])), isNotEmpty);
    });
  });

  group('fremdrift', () {
    test('streak tæller sammenhængende dage', () async {
      final today = DateTime.now();
      for (var i = 0; i < 4; i++) {
        final day = DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: i))
            .millisecondsSinceEpoch;
        db.db.execute(
          'INSERT INTO daily_activity (day, minutes_studied) VALUES (?, 20)',
          [day],
        );
      }
      final streak = await progress.streak();
      expect(streak.current, 4);
      expect(streak.activeToday, isTrue);
      expect(streak.label, '4 dage i træk');
    });

    test('streak overlever at man ikke er gået i gang i dag endnu', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      db.db.execute(
        'INSERT INTO daily_activity (day, minutes_studied) VALUES (?, 20)',
        [DateTime(yesterday.year, yesterday.month, yesterday.day).millisecondsSinceEpoch],
      );
      final streak = await progress.streak();
      expect(streak.current, 1);
      expect(streak.activeToday, isFalse);
    });

    test('en sprunget dag brækker streaken', () async {
      final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      for (final offset in [0, 1, 3, 4]) {
        db.db.execute(
          'INSERT INTO daily_activity (day, minutes_studied) VALUES (?, 20)',
          [today.subtract(Duration(days: offset)).millisecondsSinceEpoch],
        );
      }
      final streak = await progress.streak();
      expect(streak.current, 2);
      expect(streak.longest, 2);
    });

    test('ugen har syv dage, også de tomme', () async {
      await progress.logActivity(minutes: 30, questions: 4, xp: 20);
      final week = await progress.week();
      expect(week.days, hasLength(7));
      expect(week.days.last.minutesStudied, 30);
      expect(week.activeDays, 1);
      expect(week.totalMinutes, 30);
    });

    test('achievements låses op én gang og bliver låst op', () async {
      final s = await focus.start();
      await focus.finish(s.id, actualSeconds: 25 * 60, completed: true);

      final first = await progress.refreshAchievements();
      expect(first.map((a) => a.code), contains('first_session'));

      // Anden kørsel må ikke fejre det samme igen.
      final second = await progress.refreshAchievements();
      expect(second.map((a) => a.code), isNot(contains('first_session')));

      final all = await progress.achievements();
      expect(all.firstWhere((a) => a.code == 'first_session').isUnlocked, isTrue);
    });

    test('nulstilling rydder statistik men ikke indhold', () async {
      await profiles.create(displayName: 'Marcus');
      await notes.create(title: 'Bevares');
      await progress.logActivity(minutes: 30, xp: 50);
      await profiles.addXp(50);

      await progress.reset();

      expect((await progress.today()).minutesStudied, 0);
      expect((await profiles.read())!.xp, 0);
      expect(await notes.notes(), hasLength(1));
    });
  });
}
