import 'package:sqlite3/sqlite3.dart';

import 'db/local_database.dart';

/// User preferences. Stored in the same local SQLite file as everything else —
/// GlemtDet writes nothing outside its own application-support folder.
class AppSettings {
  const AppSettings({
    this.memoryActive = false,
    this.storeImages = true,
    this.keepRunningInBackground = true,
    this.retentionDays = 0,
    this.cameraDeviceId,
    this.themeMode = AppThemeMode.system,
    this.hasSeenIntro = false,
    this.aiMemoryEnabled = true,
    this.screenUnderstandingEnabled = false,
    this.microphoneEnabled = false,
    this.automaticNotesEnabled = false,
    this.gamificationEnabled = true,
  });

  /// The "Hukommelse aktiv" switch: is GlemtDet allowed to record right now.
  final bool memoryActive;

  /// Keep a reference frame with each observation.
  final bool storeImages;

  /// Keep capturing while the main window is closed.
  final bool keepRunningInBackground;

  /// Delete observations older than this. 0 means keep everything.
  final int retentionDays;

  final String? cameraDeviceId;
  final AppThemeMode themeMode;
  final bool hasSeenIntro;

  // ---- TeenBrain -------------------------------------------------------
  // Everything that can observe the user defaults to off. The one that is on
  // by default — AI memory — observes nothing on its own; it only remembers
  // what the user already typed, and the My AI page shows every line of it.

  /// Whether the assistant may retrieve and store memories.
  final bool aiMemoryEnabled;

  /// Whether the app may read the screen. Opt-in, with a visible indicator.
  final bool screenUnderstandingEnabled;

  /// Whether the app may use the microphone. Opt-in.
  final bool microphoneEnabled;

  /// Whether transcription may be turned into notes without asking each time.
  final bool automaticNotesEnabled;

  /// Streaks, XP and levels. Can be switched off entirely.
  final bool gamificationEnabled;

  AppSettings copyWith({
    bool? memoryActive,
    bool? storeImages,
    bool? keepRunningInBackground,
    int? retentionDays,
    String? cameraDeviceId,
    bool clearCameraDeviceId = false,
    AppThemeMode? themeMode,
    bool? hasSeenIntro,
    bool? aiMemoryEnabled,
    bool? screenUnderstandingEnabled,
    bool? microphoneEnabled,
    bool? automaticNotesEnabled,
    bool? gamificationEnabled,
  }) =>
      AppSettings(
        memoryActive: memoryActive ?? this.memoryActive,
        storeImages: storeImages ?? this.storeImages,
        keepRunningInBackground: keepRunningInBackground ?? this.keepRunningInBackground,
        retentionDays: retentionDays ?? this.retentionDays,
        cameraDeviceId: clearCameraDeviceId ? null : (cameraDeviceId ?? this.cameraDeviceId),
        themeMode: themeMode ?? this.themeMode,
        hasSeenIntro: hasSeenIntro ?? this.hasSeenIntro,
        aiMemoryEnabled: aiMemoryEnabled ?? this.aiMemoryEnabled,
        screenUnderstandingEnabled:
            screenUnderstandingEnabled ?? this.screenUnderstandingEnabled,
        microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
        automaticNotesEnabled: automaticNotesEnabled ?? this.automaticNotesEnabled,
        gamificationEnabled: gamificationEnabled ?? this.gamificationEnabled,
      );
}

enum AppThemeMode { system, light, dark }

class SettingsStore {
  SettingsStore(this._local);

  final LocalDatabase _local;
  Database get _db => _local.db;

  AppSettings read() {
    final rows = _db.select('SELECT key, value FROM settings');
    final map = {for (final r in rows) r['key'] as String: r['value'] as String};
    return AppSettings(
      memoryActive: map['memory_active'] == '1',
      storeImages: map['store_images'] != '0',
      keepRunningInBackground: map['background'] != '0',
      retentionDays: int.tryParse(map['retention_days'] ?? '0') ?? 0,
      cameraDeviceId: map['camera_device_id'],
      themeMode: switch (map['theme_mode']) {
        'light' => AppThemeMode.light,
        'dark' => AppThemeMode.dark,
        _ => AppThemeMode.system,
      },
      hasSeenIntro: map['seen_intro'] == '1',
      aiMemoryEnabled: map['ai_memory'] != '0',
      screenUnderstandingEnabled: map['screen_understanding'] == '1',
      microphoneEnabled: map['microphone'] == '1',
      automaticNotesEnabled: map['auto_notes'] == '1',
      gamificationEnabled: map['gamification'] != '0',
    );
  }

  void write(AppSettings settings) {
    void put(String key, String? value) {
      if (value == null) {
        _db.execute('DELETE FROM settings WHERE key = ?', [key]);
      } else {
        _db.execute(
          'INSERT INTO settings (key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          [key, value],
        );
      }
    }

    put('memory_active', settings.memoryActive ? '1' : '0');
    put('store_images', settings.storeImages ? '1' : '0');
    put('background', settings.keepRunningInBackground ? '1' : '0');
    put('retention_days', '${settings.retentionDays}');
    put('camera_device_id', settings.cameraDeviceId);
    put('theme_mode', settings.themeMode.name);
    put('seen_intro', settings.hasSeenIntro ? '1' : '0');
    put('ai_memory', settings.aiMemoryEnabled ? '1' : '0');
    put('screen_understanding', settings.screenUnderstandingEnabled ? '1' : '0');
    put('microphone', settings.microphoneEnabled ? '1' : '0');
    put('auto_notes', settings.automaticNotesEnabled ? '1' : '0');
    put('gamification', settings.gamificationEnabled ? '1' : '0');
  }
}
