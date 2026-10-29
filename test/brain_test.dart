import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/brain/brain_service.dart';
import 'package:glemtdet/brain/context_builder.dart';
import 'package:glemtdet/brain/schemas.dart';
import 'package:glemtdet/brain/search_interpreter.dart';
import 'package:glemtdet/data/db/local_database.dart';
import 'package:glemtdet/data/repositories/sqlite_chat_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_memory_store.dart';
import 'package:glemtdet/data/repositories/sqlite_note_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_profile_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_quiz_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_school_repository.dart';
import 'package:glemtdet/data/repositories/sqlite_search_index.dart';
import 'package:glemtdet/data/repositories/sqlite_timeline_repository.dart';
import 'package:glemtdet/domain/models/memory.dart';
import 'package:glemtdet/domain/models/profile.dart';
import 'package:glemtdet/domain/models/quiz.dart';
import 'package:glemtdet/domain/models/school.dart';
import 'package:glemtdet/domain/services/ai_client.dart';

/// A model that answers with whatever the test told it to.
class FakeAiClient implements AiClient {
  FakeAiClient({this.text = 'Svar.', this.structuredResult, this.failure});

  final String text;
  Object? structuredResult;
  AiFailure? failure;

  final List<AiRequest> requests = [];

  @override
  String get id => 'fake';
  @override
  String get modelLabel => 'Fake';
  @override
  bool get isConfigured => true;
  @override
  String get unconfiguredReason => '';

  @override
  Stream<AiDelta> complete(AiRequest request) async* {
    requests.add(request);
    if (failure != null) {
      yield failure!;
      return;
    }
    yield AiTextDelta(text);
    yield const AiDone();
  }

  @override
  Future<T> structured<T>(AiRequest request, AiSchema<T> schema) async {
    requests.add(request);
    if (failure != null) throw failure!;
    return structuredResult as T;
  }

  @override
  Future<AiHealth> check() async => const AiHealth.ok('Fake');
  @override
  void dispose() {}
}

void main() {
  group('søgefortolkning', () {
    const interpreter = SearchInterpreter(subjectNames: ['Matematik', 'Biologi']);
    final now = DateTime(2026, 9, 4, 12);

    test('fjerner spørgeord og fyld', () {
      final result = interpreter.interpret('Find mine noter om anden verdenskrig', now: now);
      expect(result.terms, contains('verdenskrig'));
      expect(result.terms, isNot(contains('find')));
      expect(result.terms, isNot(contains('mine')));
      expect(result.terms, isNot(contains('noter')));
    });

    test('genkender et spørgsmål om hvornår', () {
      final result = interpreter.interpret('Hvornår lærte jeg om fotosyntese?', now: now);
      expect(result.wantsWhen, isTrue);
      expect(result.terms, contains('fotosyntese'));
    });

    test('genkender et spørgsmål om hvad der er svært', () {
      final result = interpreter.interpret(
          'Hvad havde jeg svært ved i matematik sidste måned?',
          now: now);
      expect(result.wantsDifficulty, isTrue);
      expect(result.subjectName, 'Matematik');
      expect(result.after, DateTime(2026, 8));
      expect(result.before, DateTime(2026, 9));
    });

    test('forstår sidste uge som den forrige kalenderuge', () {
      // 4. september 2026 er en fredag; ugen begyndte mandag den 31. august.
      final result = interpreter.interpret('hvad lavede jeg i sidste uge', now: now);
      expect(result.after, DateTime(2026, 8, 24));
      expect(result.before, DateTime(2026, 8, 31));
    });

    test('forstår i dag og i går', () {
      expect(interpreter.interpret('hvad lavede jeg i dag', now: now).after,
          DateTime(2026, 9, 4));
      expect(interpreter.interpret('hvad lavede jeg i går', now: now).before,
          DateTime(2026, 9, 4));
    });

    test('fagnavnet bliver ikke også et søgeord', () {
      final result = interpreter.interpret('matematik brøker', now: now);
      expect(result.subjectName, 'Matematik');
      expect(result.terms, ['broeker']);
    });

    test('et tomt spørgsmål giver ingen søgeord', () {
      expect(interpreter.interpret('hvad har jeg lavet', now: now).terms, isEmpty);
    });
  });

  group('skemaer', () {
    test('quiz: multiple choice uden facit blandt mulighederne repareres', () {
      final questions = Schemas.quiz.parse({
        'questions': [
          {
            'kind': 'multiple_choice',
            'prompt': 'Hvad er 2+2?',
            'options': ['3', '5', '6'],
            'answer': '4',
            'explanation': 'To plus to er fire.',
          }
        ]
      });
      expect(questions.single.options, contains('4'));
      expect(questions.single.options.first, '4');
    });

    test('quiz: sand/falsk får altid de to muligheder', () {
      final questions = Schemas.quiz.parse({
        'questions': [
          {
            'kind': 'true_false',
            'prompt': 'Planter laver fotosyntese',
            'answer': 'Sandt',
            'explanation': 'Ja.',
          }
        ]
      });
      expect(questions.single.options, ['Sandt', 'Falsk']);
    });

    test('quiz: fritekst har ingen svarmuligheder', () {
      final questions = Schemas.quiz.parse({
        'questions': [
          {
            'kind': 'short_answer',
            'prompt': 'Forkort 4/8',
            'options': ['noget', 'andet'],
            'answer': '1/2',
            'explanation': 'Divider med fire.',
          }
        ]
      });
      expect(questions.single.options, isEmpty);
    });

    test('quiz: spørgsmål uden facit springes over', () {
      final questions = Schemas.quiz.parse({
        'questions': [
          {'kind': 'short_answer', 'prompt': 'Uden svar', 'answer': '', 'explanation': ''},
          {'kind': 'short_answer', 'prompt': 'Med svar', 'answer': '42', 'explanation': 'x'},
        ]
      });
      expect(questions, hasLength(1));
      expect(questions.single.prompt, 'Med svar');
    });

    test('quiz: intet brugbart er en fejl, ikke en tom quiz', () {
      expect(
        () => Schemas.quiz.parse({'questions': []}),
        throwsA(isA<FormatException>()),
      );
    });

    test('hukommelse: en tom liste er et gyldigt svar', () {
      expect(Schemas.memories.parse({'memories': []}), isEmpty);
    });

    test('hukommelse: rækker uden nøgle eller indhold droppes', () {
      final result = Schemas.memories.parse({
        'memories': [
          {'kind': 'fact', 'key': '', 'value': 'noget', 'confidence': 0.5},
          {'kind': 'struggle', 'key': 'k', 'value': 'Har svært ved brøker', 'confidence': 1.4},
        ]
      });
      expect(result, hasLength(1));
      expect(result.single.confidence, 1.0);
      expect(result.single.kind, MemoryKind.struggle);
    });

    test('forslag: rækker uden titel droppes', () {
      final result = Schemas.suggestions.parse({
        'suggestions': [
          {'title': '', 'reason': 'x', 'action': 'none'},
          {'title': 'Matematikaflevering i morgen', 'reason': 'Du mangler ca. 25 minutter.',
           'action': 'start_focus', 'subject': 'Matematik'},
        ]
      });
      expect(result, hasLength(1));
      expect(result.single.action, SuggestionAction.startFocus);
      expect(result.single.subjectName, 'Matematik');
    });

    test('note: tom note afvises', () {
      expect(
        () => Schemas.note.parse({'title': 'Titel', 'body': '  '}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('kontekstbygger', () {
    late Directory dir;
    late LocalDatabase db;
    late SqliteMemoryStore memories;
    late ContextBuilder builder;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('brain_test');
      db = LocalDatabase.openInMemory(dir);
      memories = SqliteMemoryStore(db);
      builder = ContextBuilder(memories);
    });

    tearDown(() {
      db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<void> seed(int count) async {
      for (var i = 0; i < count; i++) {
        await memories.remember(
          MemoryCandidate(
            kind: MemoryKind.learning,
            key: 'topic.$i',
            value: 'Brugeren har arbejdet med emne nummer $i i et eller andet fag',
          ),
          source: MemorySource.session,
        );
      }
    }

    test('budgettet holder, uanset hvor meget der ligger i databasen', () async {
      await seed(400);

      final context = await builder.build(
        query: 'emne',
        snapshot: const ContextSnapshot(profile: null),
        budget: const ContextBudget(),
      );

      expect(context.consideredCount, greaterThan(20));
      expect(context.estimatedTokens, lessThanOrEqualTo(const ContextBudget().total));
      expect(context.memories.length, lessThan(400));
    });

    test('databasen vokser, konteksten gør ikke', () async {
      await seed(20);
      final small = await builder.build(
        query: 'emne', snapshot: const ContextSnapshot(profile: null));

      await seed(400);
      final large = await builder.build(
        query: 'emne', snapshot: const ContextSnapshot(profile: null));

      expect(large.estimatedTokens, lessThanOrEqualTo(small.estimatedTokens + 200));
    });

    test('deaktiveret hukommelse kommer aldrig med', () async {
      final m = await memories.remember(
        const MemoryCandidate(
            kind: MemoryKind.preference, key: 'style', value: 'Korte forklaringer'),
        source: MemorySource.onboarding,
      );
      await memories.setActive(m.id, false);

      final context = await builder.build(
        query: 'forklaring', snapshot: const ContextSnapshot(profile: null));
      expect(context.rendered, isNot(contains('Korte forklaringer')));
    });

    test('profilen kommer altid med', () async {
      final context = await builder.build(
        query: 'hej',
        snapshot: ContextSnapshot(
          profile: Profile(displayName: 'Marcus', gradeLevel: '8. klasse',
              createdAt: DateTime.now()),
          subjects: [
            Subject(id: 1, name: 'Matematik', createdAt: DateTime.now()),
          ],
        ),
      );
      expect(context.rendered, contains('Marcus'));
      expect(context.rendered, contains('8. klasse'));
      expect(context.rendered, contains('Matematik'));
    });

    test('deadlines beskrives i dage, ikke i tidsstempler', () async {
      final now = DateTime.now();
      final context = await builder.build(
        query: 'hvad skal jeg lave',
        snapshot: ContextSnapshot(
          profile: null,
          upcoming: [
            Assignment(
              id: 1, title: 'Matematikaflevering',
              dueAt: DateTime(now.year, now.month, now.day).add(const Duration(days: 1, hours: 8)),
              createdAt: now,
            ),
          ],
        ),
      );
      expect(context.rendered, contains('Matematikaflevering'));
      expect(context.rendered, contains('i morgen'));
    });

    test('brug bliver talt, så det påvirker senere rangering', () async {
      await seed(3);
      await builder.build(query: 'emne', snapshot: const ContextSnapshot(profile: null));
      final all = await memories.all();
      expect(all.where((m) => m.useCount > 0), isNotEmpty);
    });
  });

  group('læring af quizresultater', () {
    late Directory dir;
    late LocalDatabase db;
    late BrainService brain;
    late SqliteSchoolRepository school;
    late SqliteQuizRepository quizzes;
    late SqliteMemoryStore memories;
    var memoryOn = true;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('brain_quiz_test');
      db = LocalDatabase.openInMemory(dir);
      final search = SqliteSearchIndex(db);
      await search.initialize();
      school = SqliteSchoolRepository(db);
      quizzes = SqliteQuizRepository(db, searchIndex: search);
      memories = SqliteMemoryStore(db);
      memoryOn = true;

      brain = BrainService(
        client: FakeAiClient(),
        profiles: SqliteProfileRepository(db),
        school: school,
        notes: SqliteNoteRepository(db, searchIndex: search),
        chats: SqliteChatRepository(db, searchIndex: search),
        quizzes: quizzes,
        timeline: SqliteTimelineRepository(db, searchIndex: search),
        memories: memories,
        search: search,
        memoryEnabled: () => memoryOn,
      );
    });

    tearDown(() {
      db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<(Quiz, QuizAttempt)> runQuiz({required int correctCount}) async {
      final subject = await school.createSubject('Matematik');
      final topic = await school.ensureTopic(subject.id, 'Andengradsligninger');
      final quiz = await quizzes.create(
        title: 'Andengradsligninger',
        subjectId: subject.id,
        topicId: topic.id,
        questions: const [
          QuizQuestion(id: 0, quizId: 0, kind: QuestionKind.trueFalse,
              prompt: 'Diskriminanten er b²-4ac', answer: 'Sandt'),
          QuizQuestion(id: 0, quizId: 0, kind: QuestionKind.trueFalse,
              prompt: 'To løsninger når d < 0', answer: 'Falsk'),
          QuizQuestion(id: 0, quizId: 0, kind: QuestionKind.trueFalse,
              prompt: 'Nulreglen kan bruges', answer: 'Sandt'),
          QuizQuestion(id: 0, quizId: 0, kind: QuestionKind.trueFalse,
              prompt: 'a må gerne være 0', answer: 'Falsk'),
        ],
      );

      final attempt = await quizzes.startAttempt(quiz.id);
      for (var i = 0; i < quiz.questions.length; i++) {
        await quizzes.recordAnswer(
          attemptId: attempt.id,
          questionId: quiz.questions[i].id,
          given: 'x',
          correct: i < correctCount,
        );
      }
      return (quiz, await quizzes.finishAttempt(attempt.id));
    }

    test('fejl bliver til en struggle-memory med kilde', () async {
      final (quiz, attempt) = await runQuiz(correctCount: 1);
      await brain.learnFromQuiz(quiz, attempt);

      final struggles = await memories.all(kind: MemoryKind.struggle);
      expect(struggles, hasLength(1));
      expect(struggles.single.value, contains('Andengradsligninger'));
      expect(struggles.single.source, MemorySource.quiz);

      final links = await memories.linksFor(struggles.single.id);
      expect(links.single.refTable, 'quizzes');
      expect(links.single.refId, quiz.id);
    });

    test('alle rigtige bliver til en strength-memory', () async {
      final (quiz, attempt) = await runQuiz(correctCount: 4);
      await brain.learnFromQuiz(quiz, attempt);

      expect(await memories.all(kind: MemoryKind.strength), hasLength(1));
      expect(await memories.all(kind: MemoryKind.struggle), isEmpty);
    });

    test('resultatet flytter emnets mastery', () async {
      final (quiz, attempt) = await runQuiz(correctCount: 4);
      final before = (await school.topic(quiz.topicId!))!.mastery;
      await brain.learnFromQuiz(quiz, attempt);
      final after = (await school.topic(quiz.topicId!))!.mastery;
      expect(after, greaterThan(before));
    });

    test('slået fra hukommelse skriver ingenting', () async {
      memoryOn = false;
      final (quiz, attempt) = await runQuiz(correctCount: 0);
      await brain.learnFromQuiz(quiz, attempt);
      expect(await memories.all(), isEmpty);
    });

    test('konteksten er tom, når hukommelsen er slået fra', () async {
      await memories.remember(
        const MemoryCandidate(kind: MemoryKind.fact, key: 'k', value: 'Noget om brugeren'),
        source: MemorySource.onboarding,
      );
      memoryOn = false;
      final context = await brain.buildContext(query: 'noget');
      expect(context.isEmpty, isTrue);
      expect(context.rendered, isEmpty);
    });
  });

  group('quizgenerering', () {
    late Directory dir;
    late LocalDatabase db;
    late FakeAiClient client;
    late BrainService brain;
    late SqliteSchoolRepository school;
    late SqliteNoteRepository notes;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('brain_gen_test');
      db = LocalDatabase.openInMemory(dir);
      final search = SqliteSearchIndex(db);
      await search.initialize();
      school = SqliteSchoolRepository(db);
      notes = SqliteNoteRepository(db, searchIndex: search);
      client = FakeAiClient();

      brain = BrainService(
        client: client,
        profiles: SqliteProfileRepository(db),
        school: school,
        notes: notes,
        chats: SqliteChatRepository(db, searchIndex: search),
        quizzes: SqliteQuizRepository(db, searchIndex: search),
        timeline: SqliteTimelineRepository(db, searchIndex: search),
        memories: SqliteMemoryStore(db),
        search: search,
        memoryEnabled: () => true,
      );
    });

    tearDown(() {
      db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('uden materiale bliver der ikke lavet en tom quiz', () async {
      final subject = await school.createSubject('Historie');
      expect(
        () => brain.generateQuiz(
            title: 'Tom', subjectId: subject.id, source: QuizSource.notes),
        throwsA(isA<AiFailure>()),
      );
    });

    test('en quiz ud fra noter bliver gemt med sine spørgsmål', () async {
      final subject = await school.createSubject('Biologi');
      await notes.create(
        title: 'Fotosyntese',
        bodyMd: 'Planter omdanner lys, vand og CO2 til sukker og ilt. '
            'Processen foregår i grønkornene.',
        subjectId: subject.id,
      );

      client.structuredResult = const [
        QuizQuestion(id: 0, quizId: 0, kind: QuestionKind.trueFalse,
            prompt: 'Fotosyntese foregår i grønkornene', answer: 'Sandt',
            explanation: 'Ja, i kloroplasterne.'),
      ];

      final quiz = await brain.generateQuiz(
        title: 'Fotosyntese',
        subjectId: subject.id,
        source: QuizSource.notes,
      );

      expect(quiz.questions, hasLength(1));
      expect(quiz.sourceKind, 'note');
      expect(quiz.sourceLabel, 'Lavet ud fra dine noter');

      // Materialet skal faktisk være sendt med.
      expect(client.requests.last.messages.last.text, contains('grønkornene'));
    });

    test('forslag fejler stille, så forsiden altid kan tegnes', () async {
      client.failure = const AiFailure('nede', kind: AiFailureKind.network);
      expect(await brain.suggestions(), isEmpty);
    });

    test('fritekstsvar rettes lokalt, når modellen ikke svarer', () async {
      client.failure = const AiFailure('nede', kind: AiFailureKind.network);
      final graded = await brain.gradeAnswer(
        question: const QuizQuestion(id: 1, quizId: 1, kind: QuestionKind.shortAnswer,
            prompt: 'Forkort 4/8', answer: '1/2'),
        given: '1/2',
      );
      expect(graded.correct, isTrue);
    });
  });
}
