/// Database schema and migrations.
///
/// Everything lives in one local SQLite file inside the OS application-support
/// directory. Nothing leaves the machine. Reference frames are stored as JPEG
/// files next to the database, not as blobs, so "delete all images" is a
/// directory removal that is easy to verify.
library;

const int kSchemaVersion = 2;

/// Ordered migrations. Index 0 upgrades an empty database to version 1,
/// index 1 takes version 1 to version 2.
///
/// v1 is GlemtDet's visual memory; v2 is TeenBrain. They share a file and a
/// connection but not a single table, so an existing GlemtDet install upgrades
/// in place without losing anything.
const List<List<String>> kMigrations = [
  // ---- v1 -------------------------------------------------------------
  [
    '''
    CREATE TABLE objects (
      key                TEXT PRIMARY KEY,
      label              TEXT NOT NULL,
      first_seen         INTEGER NOT NULL,
      last_seen          INTEGER NOT NULL,
      observation_count  INTEGER NOT NULL DEFAULT 0,
      best_confidence    REAL NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE places (
      key                TEXT PRIMARY KEY,
      label              TEXT NOT NULL,
      first_seen         INTEGER NOT NULL,
      last_seen          INTEGER NOT NULL,
      observation_count  INTEGER NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE observations (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      object_key         TEXT NOT NULL REFERENCES objects(key) ON DELETE CASCADE,
      object_label       TEXT NOT NULL,
      confidence         REAL NOT NULL,
      seen_at            INTEGER NOT NULL,
      place_key          TEXT,
      place_label        TEXT,
      place_confidence   REAL,
      image_path         TEXT,
      bbox_l             REAL,
      bbox_t             REAL,
      bbox_w             REAL,
      bbox_h             REAL,
      raw_labels         TEXT,
      backend            TEXT NOT NULL DEFAULT 'unknown'
    )
    ''',
    'CREATE INDEX idx_obs_seen_at ON observations(seen_at DESC)',
    'CREATE INDEX idx_obs_object ON observations(object_key, seen_at DESC)',
    'CREATE INDEX idx_obs_place ON observations(place_key, seen_at DESC)',
    '''
    CREATE TABLE object_place_stats (
      object_key   TEXT NOT NULL,
      place_key    TEXT NOT NULL,
      place_label  TEXT NOT NULL,
      count        INTEGER NOT NULL DEFAULT 0,
      last_seen    INTEGER NOT NULL,
      PRIMARY KEY (object_key, place_key)
    )
    ''',
    '''
    CREATE TABLE settings (
      key    TEXT PRIMARY KEY,
      value  TEXT NOT NULL
    )
    ''',
  ],

  // ---- v2: TeenBrain --------------------------------------------------
  [
    // -- Identitet og progression ---------------------------------------
    '''
    CREATE TABLE profile (
      id                    INTEGER PRIMARY KEY CHECK (id = 1),
      display_name          TEXT NOT NULL,
      grade_level           TEXT,
      created_at            INTEGER NOT NULL,
      onboarded_at          INTEGER,
      xp                    INTEGER NOT NULL DEFAULT 0,
      gamification_enabled  INTEGER NOT NULL DEFAULT 1
    )
    ''',

    // -- Skole -----------------------------------------------------------
    '''
    CREATE TABLE subjects (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      name         TEXT NOT NULL,
      color_token  TEXT NOT NULL DEFAULT 'blue',
      sort_order   INTEGER NOT NULL DEFAULT 0,
      archived     INTEGER NOT NULL DEFAULT 0,
      created_at   INTEGER NOT NULL
    )
    ''',
    'CREATE UNIQUE INDEX idx_subject_name ON subjects(name)',
    '''
    CREATE TABLE topics (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id   INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
      name         TEXT NOT NULL,
      mastery      REAL NOT NULL DEFAULT 0,
      first_seen   INTEGER NOT NULL,
      last_worked  INTEGER,
      created_at   INTEGER NOT NULL
    )
    ''',
    'CREATE UNIQUE INDEX idx_topic_subject_name ON topics(subject_id, name)',
    '''
    CREATE TABLE assignments (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id         INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
      title              TEXT NOT NULL,
      description        TEXT,
      due_at             INTEGER,
      estimated_minutes  INTEGER,
      completed_at       INTEGER,
      created_at         INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_assignment_due ON assignments(completed_at, due_at)',

    // -- Noter -----------------------------------------------------------
    '''
    CREATE TABLE notes (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id  INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
      topic_id    INTEGER REFERENCES topics(id) ON DELETE SET NULL,
      title       TEXT NOT NULL,
      body_md     TEXT NOT NULL DEFAULT '',
      source      TEXT NOT NULL DEFAULT 'manual',
      pinned      INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL,
      updated_at  INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_note_subject ON notes(subject_id, updated_at DESC)',
    'CREATE INDEX idx_note_updated ON notes(updated_at DESC)',

    // -- Samtaler --------------------------------------------------------
    '''
    CREATE TABLE conversations (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      title       TEXT NOT NULL DEFAULT 'Ny samtale',
      created_at  INTEGER NOT NULL,
      updated_at  INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_conversation_updated ON conversations(updated_at DESC)',
    '''
    CREATE TABLE messages (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      conversation_id  INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      role             TEXT NOT NULL,
      content          TEXT NOT NULL,
      created_at       INTEGER NOT NULL,
      tool_calls_json  TEXT
    )
    ''',
    'CREATE INDEX idx_message_conversation ON messages(conversation_id, created_at)',

    // -- Quizzer ---------------------------------------------------------
    '''
    CREATE TABLE quizzes (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id   INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
      topic_id     INTEGER REFERENCES topics(id) ON DELETE SET NULL,
      title        TEXT NOT NULL,
      source_kind  TEXT NOT NULL DEFAULT 'topic',
      source_ref   TEXT,
      created_at   INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX idx_quiz_created ON quizzes(created_at DESC)',
    '''
    CREATE TABLE quiz_questions (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      quiz_id       INTEGER NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
      kind          TEXT NOT NULL,
      prompt        TEXT NOT NULL,
      options_json  TEXT,
      answer        TEXT NOT NULL,
      explanation   TEXT,
      position      INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_question_quiz ON quiz_questions(quiz_id, position)',
    '''
    CREATE TABLE quiz_attempts (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      quiz_id      INTEGER NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
      started_at   INTEGER NOT NULL,
      finished_at  INTEGER,
      score        INTEGER NOT NULL DEFAULT 0,
      total        INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_attempt_quiz ON quiz_attempts(quiz_id, started_at DESC)',
    '''
    CREATE TABLE quiz_answers (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      attempt_id   INTEGER NOT NULL REFERENCES quiz_attempts(id) ON DELETE CASCADE,
      question_id  INTEGER NOT NULL REFERENCES quiz_questions(id) ON DELETE CASCADE,
      given        TEXT NOT NULL DEFAULT '',
      correct      INTEGER NOT NULL DEFAULT 0,
      ai_feedback  TEXT
    )
    ''',
    'CREATE INDEX idx_answer_attempt ON quiz_answers(attempt_id)',

    // -- Fokus -----------------------------------------------------------
    '''
    CREATE TABLE focus_sessions (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id       INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
      topic_id         INTEGER REFERENCES topics(id) ON DELETE SET NULL,
      assignment_id    INTEGER REFERENCES assignments(id) ON DELETE SET NULL,
      started_at       INTEGER NOT NULL,
      ended_at         INTEGER,
      planned_minutes  INTEGER NOT NULL DEFAULT 25,
      actual_seconds   INTEGER NOT NULL DEFAULT 0,
      completed        INTEGER NOT NULL DEFAULT 0,
      notes            TEXT
    )
    ''',
    'CREATE INDEX idx_focus_started ON focus_sessions(started_at DESC)',

    // -- Timeline --------------------------------------------------------
    // En række pr. ting brugeren har lavet. Alt andet skriver hertil, så
    // tidslinjen og søgningen har én rygrad at hænge på.
    '''
    CREATE TABLE timeline_events (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      kind        TEXT NOT NULL,
      subject_id  INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
      ref_table   TEXT,
      ref_id      INTEGER,
      title       TEXT NOT NULL,
      summary     TEXT,
      started_at  INTEGER NOT NULL,
      ended_at    INTEGER
    )
    ''',
    'CREATE INDEX idx_timeline_started ON timeline_events(started_at DESC)',
    'CREATE INDEX idx_timeline_subject ON timeline_events(subject_id, started_at DESC)',

    // -- Hukommelse ------------------------------------------------------
    // Appens hjerte. `active` er brugerens afbryder: en deaktiveret memory
    // beholder sin række og sin oprindelse, men kommer aldrig i en prompt.
    '''
    CREATE TABLE memories (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      kind         TEXT NOT NULL,
      key          TEXT NOT NULL,
      value        TEXT NOT NULL,
      confidence   REAL NOT NULL DEFAULT 0.5,
      source       TEXT NOT NULL DEFAULT 'inferred',
      subject_id   INTEGER REFERENCES subjects(id) ON DELETE SET NULL,
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL,
      last_used_at INTEGER,
      use_count    INTEGER NOT NULL DEFAULT 0,
      pinned       INTEGER NOT NULL DEFAULT 0,
      active       INTEGER NOT NULL DEFAULT 1
    )
    ''',
    'CREATE UNIQUE INDEX idx_memory_kind_key ON memories(kind, key)',
    'CREATE INDEX idx_memory_active ON memories(active, kind)',
    '''
    CREATE TABLE memory_links (
      memory_id  INTEGER NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
      ref_table  TEXT NOT NULL,
      ref_id     INTEGER NOT NULL,
      PRIMARY KEY (memory_id, ref_table, ref_id)
    )
    ''',

    // -- Gamification ----------------------------------------------------
    '''
    CREATE TABLE achievements (
      code         TEXT PRIMARY KEY,
      unlocked_at  INTEGER,
      progress     REAL NOT NULL DEFAULT 0
    )
    ''',
    '''
    CREATE TABLE daily_activity (
      day                INTEGER PRIMARY KEY,
      minutes_studied    INTEGER NOT NULL DEFAULT 0,
      questions_answered INTEGER NOT NULL DEFAULT 0,
      xp_earned          INTEGER NOT NULL DEFAULT 0
    )
    ''',

    // -- Søgning ---------------------------------------------------------
    // FTS5-tabellen oprettes af SearchIndex, som først verificerer at den
    // bundtede SQLite faktisk har modulet. Kortet her er almindelig SQL og
    // findes altid, så LIKE-faldbacken har et sted at kigge.
    '''
    CREATE TABLE search_map (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      ref_table    TEXT NOT NULL,
      ref_id       INTEGER NOT NULL,
      subject_id   INTEGER,
      occurred_at  INTEGER NOT NULL,
      title        TEXT NOT NULL,
      body         TEXT NOT NULL DEFAULT '',
      folded       TEXT NOT NULL DEFAULT ''
    )
    ''',
    'CREATE UNIQUE INDEX idx_search_ref ON search_map(ref_table, ref_id)',
    'CREATE INDEX idx_search_occurred ON search_map(occurred_at DESC)',
  ],
];
