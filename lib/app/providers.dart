/// Dependency wiring.
///
/// Everything the app uses is constructed here and nowhere else. That is what
/// keeps two promises real: `aiStackProvider` is the single seam between
/// TeenBrain and a language model, and `visionStackProvider` is the single seam
/// between it and platform computer vision.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_stack.dart';
import '../ai/api_key_store.dart';
import '../brain/brain_service.dart';
import '../brain/live_notes_service.dart';
import '../brain/schemas.dart';
import '../core/app_paths.dart';
import '../data/db/local_database.dart';
import '../data/repositories/sqlite_chat_repository.dart';
import '../data/repositories/sqlite_focus_repository.dart';
import '../data/repositories/sqlite_memory_repository.dart';
import '../data/repositories/sqlite_memory_store.dart';
import '../data/repositories/sqlite_note_repository.dart';
import '../data/repositories/sqlite_profile_repository.dart';
import '../data/repositories/sqlite_progress_repository.dart';
import '../data/repositories/sqlite_quiz_repository.dart';
import '../data/repositories/sqlite_school_repository.dart';
import '../data/repositories/sqlite_search_index.dart';
import '../data/repositories/sqlite_timeline_repository.dart';
import '../data/settings_store.dart';
import '../domain/models/chat.dart';
import '../domain/models/focus.dart';
import '../domain/models/memory.dart';
import '../domain/models/note.dart';
import '../domain/models/observation.dart';
import '../domain/models/profile.dart';
import '../domain/models/progress.dart';
import '../domain/models/quiz.dart';
import '../domain/models/school.dart';
import '../domain/models/timeline.dart';
import '../domain/repositories/chat_repository.dart';
import '../domain/repositories/focus_repository.dart';
import '../domain/repositories/memory_repository.dart';
import '../domain/repositories/memory_store.dart';
import '../domain/repositories/note_repository.dart';
import '../domain/repositories/profile_repository.dart';
import '../domain/repositories/progress_repository.dart';
import '../domain/repositories/quiz_repository.dart';
import '../domain/repositories/school_repository.dart';
import '../domain/repositories/search_index.dart';
import '../domain/repositories/timeline_repository.dart';
import '../domain/services/ai_client.dart';
import '../domain/services/answer_engine.dart';
import '../domain/services/detection_services.dart';
import '../domain/services/memory_service.dart';
import '../domain/services/transcriber.dart';
import '../domain/services/vision_service.dart';
import '../vision/interpretation/local_answer_engine.dart';
import '../vision/interpretation/taxonomy_object_detection_service.dart';
import '../vision/interpretation/taxonomy_scene_recognition_service.dart';
import '../transcription/transcription_stack.dart';
import '../vision/vision_stack.dart';

/// Everything that has to exist before the first frame is painted.
class AppBootstrap {
  AppBootstrap({
    required this.database,
    required this.settingsStore,
    required this.settings,
    required this.searchIndex,
    required this.profiles,
    required this.school,
    required this.notes,
    required this.chats,
    required this.quizzes,
    required this.focus,
    required this.timeline,
    required this.memories,
    required this.progress,
    required this.repository,
    required this.apiKey,
  });

  final LocalDatabase database;
  final SettingsStore settingsStore;
  final AppSettings settings;

  final SqliteSearchIndex searchIndex;
  final ProfileRepository profiles;
  final SchoolRepository school;
  final NoteRepository notes;
  final ChatRepository chats;
  final QuizRepository quizzes;
  final FocusRepository focus;
  final TimelineRepository timeline;
  final MemoryStore memories;
  final ProgressRepository progress;

  /// GlemtDet's visual memory. Kept wired so its pages still work.
  final SqliteMemoryRepository repository;

  final String? apiKey;
}

final apiKeyStoreProvider = Provider<ApiKeyStore>((ref) => ApiKeyStore());

final bootstrapProvider = FutureProvider<AppBootstrap>((ref) async {
  final dir = await AppPaths.resolveDataDirectory();
  final database = await LocalDatabase.open(dir);

  final searchIndex = SqliteSearchIndex(database);
  await searchIndex.initialize();

  final repository = SqliteMemoryRepository(database);
  await repository.initialize();

  final settingsStore = SettingsStore(database);

  ref.onDispose(database.close);

  return AppBootstrap(
    database: database,
    settingsStore: settingsStore,
    settings: settingsStore.read(),
    searchIndex: searchIndex,
    profiles: SqliteProfileRepository(database),
    school: SqliteSchoolRepository(database),
    notes: SqliteNoteRepository(database, searchIndex: searchIndex),
    chats: SqliteChatRepository(database, searchIndex: searchIndex),
    quizzes: SqliteQuizRepository(database, searchIndex: searchIndex),
    focus: SqliteFocusRepository(database),
    timeline: SqliteTimelineRepository(database, searchIndex: searchIndex),
    memories: SqliteMemoryStore(database),
    progress: SqliteProgressRepository(database),
    repository: repository,
    apiKey: await ref.watch(apiKeyStoreProvider).read(),
  );
});

AppBootstrap _boot(Ref ref) => ref.watch(bootstrapProvider).requireValue;

// ------------------------------------------------------------- repositories

final searchIndexProvider = Provider<SearchIndex>((ref) => _boot(ref).searchIndex);
final profileRepositoryProvider = Provider<ProfileRepository>((ref) => _boot(ref).profiles);
final schoolRepositoryProvider = Provider<SchoolRepository>((ref) => _boot(ref).school);
final noteRepositoryProvider = Provider<NoteRepository>((ref) => _boot(ref).notes);
final chatRepositoryProvider = Provider<ChatRepository>((ref) => _boot(ref).chats);
final quizRepositoryProvider = Provider<QuizRepository>((ref) => _boot(ref).quizzes);
final focusRepositoryProvider = Provider<FocusRepository>((ref) => _boot(ref).focus);
final timelineRepositoryProvider = Provider<TimelineRepository>((ref) => _boot(ref).timeline);
final memoryStoreProvider = Provider<MemoryStore>((ref) => _boot(ref).memories);
final progressRepositoryProvider = Provider<ProgressRepository>((ref) => _boot(ref).progress);

/// GlemtDet's visual memory repository.
final memoryRepositoryProvider = Provider<MemoryRepository>((ref) => _boot(ref).repository);

// ---------------------------------------------------------------- settings

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => _boot(ref).settings;

  void _persist(AppSettings next) {
    state = next;
    _boot(ref).settingsStore.write(next);
  }

  void setThemeMode(AppThemeMode mode) => _persist(state.copyWith(themeMode: mode));
  void setRetentionDays(int value) => _persist(state.copyWith(retentionDays: value));

  void setAiMemory(bool value) => _persist(state.copyWith(aiMemoryEnabled: value));
  void setScreenUnderstanding(bool value) =>
      _persist(state.copyWith(screenUnderstandingEnabled: value));
  void setMicrophone(bool value) => _persist(state.copyWith(microphoneEnabled: value));
  void setAutomaticNotes(bool value) => _persist(state.copyWith(automaticNotesEnabled: value));
  void setGamification(bool value) => _persist(state.copyWith(gamificationEnabled: value));

  // GlemtDet's switches, still honoured by its own pages.
  void setMemoryActive(bool value) => _persist(state.copyWith(memoryActive: value));
  void setStoreImages(bool value) => _persist(state.copyWith(storeImages: value));
  void setBackground(bool value) => _persist(state.copyWith(keepRunningInBackground: value));
  void setCameraDevice(String? id) =>
      _persist(state.copyWith(cameraDeviceId: id, clearCameraDeviceId: id == null));
  void markIntroSeen() => _persist(state.copyWith(hasSeenIntro: true));
}

// ---------------------------------------------------------------------- AI

/// The stored key, as its own notifier so changing it rebuilds the client.
final apiKeyProvider = NotifierProvider<ApiKeyController, String?>(ApiKeyController.new);

class ApiKeyController extends Notifier<String?> {
  @override
  String? build() => _boot(ref).apiKey;

  Future<void> save(String key) async {
    await ref.read(apiKeyStoreProvider).write(key);
    state = key.trim();
  }

  Future<void> clear() async {
    await ref.read(apiKeyStoreProvider).clear();
    state = null;
  }
}

/// The single seam between TeenBrain and a language model.
final aiStackProvider = Provider<AiClient>((ref) {
  final client = AiStack.forKey(ref.watch(apiKeyProvider));
  ref.onDispose(client.dispose);
  return client;
});

final brainProvider = Provider<BrainService>((ref) {
  return BrainService(
    client: ref.watch(aiStackProvider),
    profiles: ref.watch(profileRepositoryProvider),
    school: ref.watch(schoolRepositoryProvider),
    notes: ref.watch(noteRepositoryProvider),
    chats: ref.watch(chatRepositoryProvider),
    quizzes: ref.watch(quizRepositoryProvider),
    timeline: ref.watch(timelineRepositoryProvider),
    memories: ref.watch(memoryStoreProvider),
    search: ref.watch(searchIndexProvider),
    // Read, not watch: the switch is consulted per call, and a change should
    // not tear down and rebuild the service mid-conversation.
    memoryEnabled: () => ref.read(settingsProvider).aiMemoryEnabled,
  );
});

final aiHealthProvider = FutureProvider<AiHealth>((ref) {
  return ref.watch(aiStackProvider).check();
});

// -------------------------------------------------------------- Live Notes

/// The single seam between TeenBrain and a speech recogniser.
final transcriptionStackProvider =
    Provider<Transcriber>((ref) => TranscriptionStack.forCurrentPlatform());

final liveNotesProvider = Provider<LiveNotesService>((ref) {
  final service = LiveNotesService(
    transcriber: ref.watch(transcriptionStackProvider),
    // Read, not watch: the switch is consulted per start, and flipping it
    // should not tear down a running session's object mid-sentence.
    microphoneEnabled: () => ref.read(settingsProvider).microphoneEnabled,
  );
  ref.onDispose(service.dispose);
  return service;
});

final liveNotesStateProvider = StreamProvider<LiveNotesState>((ref) {
  return ref.watch(liveNotesProvider).states;
});

/// Current state with the service's synchronous value as the seed, so the page
/// never flashes an empty frame while waiting for the first stream event.
final currentLiveNotesProvider = Provider<LiveNotesState>((ref) {
  final service = ref.watch(liveNotesProvider);
  return ref.watch(liveNotesStateProvider).maybeWhen(
        data: (s) => s,
        orElse: () => service.state,
      );
});

// ------------------------------------------------------------- invalidation

/// Bumped whenever content changes, so list providers refetch without polling.
final dataRevisionProvider = NotifierProvider<DataRevision, int>(DataRevision.new);

class DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

// ------------------------------------------------------------------ reads

final profileProvider = FutureProvider<Profile?>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(profileRepositoryProvider).read();
});

final subjectsProvider = FutureProvider<List<Subject>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(schoolRepositoryProvider).subjects();
});

final subjectSummariesProvider = FutureProvider<List<SubjectSummary>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(schoolRepositoryProvider).summaries();
});

final subjectSummaryProvider = FutureProvider.family<SubjectSummary?, int>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(schoolRepositoryProvider).summary(id);
});

final upcomingAssignmentsProvider = FutureProvider<List<Assignment>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(schoolRepositoryProvider).upcoming(limit: 6);
});

final assignmentsProvider =
    FutureProvider.family<List<Assignment>, int?>((ref, subjectId) {
  ref.watch(dataRevisionProvider);
  return ref
      .watch(schoolRepositoryProvider)
      .assignments(includeCompleted: true, subjectId: subjectId);
});

final notesProvider = FutureProvider.family<List<Note>, int?>((ref, subjectId) {
  ref.watch(dataRevisionProvider);
  return ref.watch(noteRepositoryProvider).notes(subjectId: subjectId);
});

final noteProvider = FutureProvider.family<Note?, int>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(noteRepositoryProvider).note(id);
});

final conversationsProvider = FutureProvider<List<Conversation>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(chatRepositoryProvider).conversations();
});

final messagesProvider = FutureProvider.family<List<ChatMessage>, int>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(chatRepositoryProvider).messages(id);
});

final quizzesProvider = FutureProvider<List<Quiz>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(quizRepositoryProvider).quizzes();
});

final quizProvider = FutureProvider.family<Quiz?, int>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(quizRepositoryProvider).quiz(id);
});

final quizAttemptProvider = FutureProvider.family<QuizAttempt?, int>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(quizRepositoryProvider).attempt(id);
});

final timelineDaysProvider = FutureProvider<List<TimelineDay>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(timelineRepositoryProvider).days();
});

final memoriesProvider = FutureProvider<List<Memory>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(memoryStoreProvider).all();
});

final recentFocusProvider = FutureProvider<List<FocusSession>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(focusRepositoryProvider).recent(limit: 10);
});

final weeklyProgressProvider = FutureProvider<WeeklyProgress>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(progressRepositoryProvider).week();
});

final achievementsProvider = FutureProvider<List<Achievement>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(progressRepositoryProvider).achievements();
});

/// The dashboard's focus suggestions.
///
/// Kept out of [dataRevisionProvider] on purpose: regenerating them on every
/// write would cost a model call each time a note is saved. The dashboard
/// refreshes them explicitly.
final suggestionsProvider = FutureProvider<List<FocusSuggestion>>((ref) {
  return ref.watch(brainProvider).suggestions();
});

// ------------------------------------------------------ GlemtDet (retained)

final visionStackProvider = Provider<VisionStack>((ref) => VisionStack.forCurrentPlatform());

final objectDetectionProvider =
    Provider<ObjectDetectionService>((ref) => TaxonomyObjectDetectionService());

final sceneRecognitionProvider =
    Provider<SceneRecognitionService>((ref) => TaxonomySceneRecognitionService());

final memoryServiceProvider = Provider<MemoryService>((ref) {
  final stack = ref.watch(visionStackProvider);
  final service = MemoryService(
    camera: stack.camera,
    analyzer: stack.analyzer,
    objectDetection: ref.watch(objectDetectionProvider),
    sceneRecognition: ref.watch(sceneRecognitionProvider),
    repository: ref.watch(memoryRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final memoryStateProvider = StreamProvider<MemoryState>((ref) {
  return ref.watch(memoryServiceProvider).states;
});

final currentMemoryStateProvider = Provider<MemoryState>((ref) {
  final service = ref.watch(memoryServiceProvider);
  return ref.watch(memoryStateProvider).maybeWhen(
        data: (s) => s,
        orElse: () => service.state,
      );
});

final answerEngineProvider = Provider<AnswerEngine>((ref) {
  return LocalAnswerEngine(ref.watch(memoryRepositoryProvider));
});

final memoryRevisionProvider = NotifierProvider<MemoryRevision, int>(MemoryRevision.new);

class MemoryRevision extends Notifier<int> {
  @override
  int build() {
    final service = ref.watch(memoryServiceProvider);
    final sub = service.events.listen((_) => state = state + 1);
    ref.onDispose(sub.cancel);
    return 0;
  }

  void bump() => state = state + 1;
}

final recentObservationsProvider = FutureProvider<List<Observation>>((ref) {
  ref.watch(memoryRevisionProvider);
  return ref.watch(memoryRepositoryProvider).latestPerObject(limit: 8);
});

final historyProvider = FutureProvider.family<List<Observation>, HistoryFilter>((ref, filter) {
  ref.watch(memoryRevisionProvider);
  return ref.watch(memoryRepositoryProvider).history(filter);
});

final trackedObjectsProvider = FutureProvider<List<TrackedObject>>((ref) {
  ref.watch(memoryRevisionProvider);
  return ref.watch(memoryRepositoryProvider).objects();
});

final objectObservationsProvider = FutureProvider.family<List<Observation>, String>((ref, key) {
  ref.watch(memoryRevisionProvider);
  return ref.watch(memoryRepositoryProvider).observationsFor(key);
});

final objectHabitsProvider = FutureProvider.family<List<PlaceHabit>, String>((ref, key) {
  ref.watch(memoryRevisionProvider);
  return ref.watch(memoryRepositoryProvider).habitsFor(key);
});

final trackedObjectProvider = FutureProvider.family<TrackedObject?, String>((ref, key) {
  ref.watch(memoryRevisionProvider);
  return ref.watch(memoryRepositoryProvider).object(key);
});

final storageStatsProvider = FutureProvider<StorageStats>((ref) {
  ref.watch(memoryRevisionProvider);
  ref.watch(dataRevisionProvider);
  return ref.watch(memoryRepositoryProvider).stats();
});

final cameraDevicesProvider = FutureProvider<List<CameraDevice>>((ref) async {
  final stack = ref.watch(visionStackProvider);
  if (!stack.camera.isSupported) return const [];
  try {
    return await stack.camera.listDevices();
  } catch (e) {
    debugPrint('Kunne ikke hente kameraliste: $e');
    return const [];
  }
});

final backendVocabularyProvider = FutureProvider<List<String>>((ref) async {
  try {
    return await ref.watch(visionStackProvider).analyzer.vocabulary();
  } catch (_) {
    return const [];
  }
});

/// Where the app's data lives, for the Privacy page.
Directory teenBrainDataDirectory() => AppPaths.dataDirectory();

/// GlemtDet's pages still call it by its old name.
Directory glemtDetDataDirectory() => AppPaths.dataDirectory();
