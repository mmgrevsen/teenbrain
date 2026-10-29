# TeenBrain — arkitektur og plan

En personlig AI-"second brain" til teenagere på 13–18 år. Appen husker ting for
brugeren og lærer, hvordan de fungerer. Den er ikke en chatklient med en
databasefil ved siden af; hukommelsen er produktet, og chatten er én af flere
måder at komme til den på.

Dette dokument blev skrevet **før** implementeringen og er opdateret efter.
Status pr. trin står i afsnit 12; afvigelserne fra den oprindelige plan står i
afsnit 14. Det beskriver hvad der er bygget, hvad der er genbrugt fra den
eksisterende kodebase, og — vigtigst — hvad der **ikke** er bygget.

> **Status:** MVP'ens tolv punkter er bygget og kører. 252 tests passerer,
> `flutter analyze` er ren, og `flutter build macos --release` producerer en
> app der starter. Fase 2 (transskription, skærmforståelse, mobil) er ikke
> bygget og er markeret som sådan i appen.

---

## 1. Udgangspunktet: hvad der allerede ligger her

Projektmappen indeholder **GlemtDet**, en færdig og velfungerende Flutter-app:
en lokal visuel hukommelse, der genkender ting med kameraet og svarer på
"hvor lagde jeg mine AirPods?". 8.046 linjer app-kode, 1.374 linjer test, 95
tests der alle passer på Flutter 3.47.2.

Den kode er god, og den bliver ikke smidt væk.

### Beslutning: TeenBrain overtager appen, GlemtDet-koden bevares

TeenBrain bliver det, appen er. GlemtDets **infrastruktur** genbruges direkte og
udbygges. GlemtDets **produktsider** (Scanner, Objekter, kamera-hukommelsen)
fjernes fra navigationen, men filerne og deres tests bliver liggende i repoet
under `lib/vision/` og `lib/features/objects/` m.fl. Intet slettes. Skulle
kamera-hukommelsen skulle bruges igen, er den et navigationspunkt fra at være
tilbage.

Grunden er ærlig: "hvor lagde jeg mine nøgler" er et andet produkt end "hjælp
mig med min matematikaflevering". At blande dem giver en app uden identitet.
Men infrastrukturen bagved er den samme.

### Hvad der genbruges — og hvad der er nyt

| Eksisterende fil | Status i TeenBrain |
|---|---|
| `lib/app/theme.dart` | **Genbruges, udvides.** Token-baseret farvesystem, light/dark, `Insets`. Designsproget er allerede Apple/Notion-minimalistisk. Tilføjes: større radier, blødere skygger, mobil-typografiskala. |
| `lib/shared/widgets/primitives.dart` | **Genbruges, udvides.** `Panel`, `AppButton`, `EmptyState`, `SectionHeading`, `_Hoverable`. Tilføjes: `Chip`, `ProgressRing`, `StreakBadge`, `SkeletonBox`. |
| `lib/shared/widgets/page_body.dart` | **Genbruges.** `PageBody` + `PageTitle` giver ensartede marginer og maks-bredde. |
| `lib/data/db/local_database.dart` | **Genbruges direkte.** WAL, foreign keys, versionerede migrationer, in-memory-variant til test. |
| `lib/data/db/schema.dart` | **Udvides.** v1 bevares uændret (GlemtDets tabeller). Ny migration v2 tilføjer TeenBrains skema. Eksisterende databaser migrerer uden datatab. |
| `lib/data/settings_store.dart` | **Udvides** med TeenBrains indstillinger og privacy-flag. |
| `lib/core/app_paths.dart` | **Udvides.** Virker på macOS/Windows/Linux i dag. `path_provider` tilføjes for iOS/Android, hvor sandbox-stien ikke kan udledes. |
| `lib/core/time_format.dart` | **Genbruges direkte.** `greeting()` giver "Godmorgen"/"Godaften" ud fra klokkeslæt — præcis det, forsiden skal bruge. `whenPhrase`, `dayHeading`, `shortAgo` bruges i Timeline. |
| `lib/core/danish.dart` | **Genbruges delvist.** `foldDanish()` (æøå → søgbart) bruges i søgningen. Objekt-grammatikken er GlemtDet-specifik og rører vi ikke. |
| `lib/core/fuzzy.dart` | **Genbruges direkte.** Levenshtein + `termScore` giver stavefejl-tolerant søgning. |
| `lib/app/navigation.dart` | **Udvides.** Sealed route-hierarki; nye destinationer tilføjes, GlemtDets bevares som ubrugte klasser. |
| `lib/features/shell/app_shell.dart` | **Omskrives med genbrug.** Sidebar-mønsteret og `_SidebarItem` beholdes; der tilføjes responsivt layout med bottom navigation under 700 px bredde. |
| `lib/vision/sampling/` | **Genbruges til Screen Understanding.** `IntelligentSampler` (backoff, scene-ændring, mørke-detektion) og `ObservationDebouncer` er kadence-logik uden kamera-afhængighed. |
| `lib/domain/services/vision_service.dart` | **Genbruges som interface.** `FrameAnalyzer` beskriver præcis det, skærmforståelse skal bruge. |
| `macos/Runner/GlemtDet/VisionAnalyzer.swift` | **Genbruges.** On-device Apple Vision. Udvides med tekstgenkendelse (`VNRecognizeTextRequest`) til skærmlæsning. |
| `macos/Runner/GlemtDet/FrameStore.swift`, `SystemPaths.swift` | **Genbruges.** |
| `macos/Runner/GlemtDet/CameraController.swift` | **Bevares urørt.** Ny `ScreenCaptureController.swift` ved siden af. |
| `lib/vision/taxonomy/`, `lib/vision/apple/apple_camera_service.dart`, `lib/features/objects/`, `lib/features/scanner/`, `lib/features/history/` | **Bevares i repoet, ude af navigationen.** Tests bevares og skal blive ved med at passe. |

---

## 2. Teknologivalg

**Flutter 3.47 / Dart 3.13.** Valget er allerede truffet i dette repo, og det er
det rigtige valg til briefet: ét kodebase til macOS, Windows, iPhone og Android,
kompileret til native maskinkode, med fuld kontrol over hver eneste pixel — som
er nødvendigt, når UI'et skal føles kommercielt og ikke som et widget-katalog.
Alternativet, Electron + React, ville koste 150 MB RAM i tomgang og aldrig føles
som en Apple-app. Tauri er lettere, men har ingen troværdig mobil-historie.

**Riverpod 3** til state. Allerede i brug, compile-time-sikkert, og providers
gør det trivielt at bytte AI-backend ud i test.

**SQLite via `package:sqlite3`** som database. Rigtig relationel database med
transaktioner, indekser og fuldtekstsøgning — ikke en JSON-fil. Pakken bundter
SQLite selv gennem Dart build hooks, så det er den samme motor på alle fire
platforme, inklusive Windows hvor der ikke er et systembibliotek at falde
tilbage på.

**Claude API (`claude-opus-5` / `claude-sonnet-5`)** som AI-lag, bag et
interface.

### Nye afhængigheder

| Pakke | Hvorfor |
|---|---|
| `http` | Kald til Anthropic API. Streaming via SSE. |
| `path_provider` | Sandbox-stier på iOS/Android. Desktop bruger fortsat `AppPaths`. |
| `flutter_secure_storage` | API-nøglen i macOS Keychain / Windows Credential Manager / iOS Keychain / Android Keystore. Nøglen rører aldrig SQLite-filen. |
| `sqlite3_flutter_libs` | SQLite-binæren på iOS/Android. |
| `record` *(fase 2)* | Mikrofonoptagelse til Live Notes. |
| `intl` | Datoformatering. |

---

## 3. Arkitektur i lag

```
┌─────────────────────────────────────────────────────────────┐
│  features/            én mappe pr. side, kun UI              │
│  home · chat · notes · subjects · quiz · focus               │
│  timeline · search · myai · privacy · settings · onboarding  │
└───────────────────────────┬─────────────────────────────────┘
                            │ Riverpod providers (app/providers.dart)
┌───────────────────────────▼─────────────────────────────────┐
│  domain/              modeller + interfaces. Ved intet om    │
│                       Anthropic, SQLite eller Flutter.       │
│  AiClient · MemoryStore · NoteRepository · QuizEngine        │
│  StudyRepository · TimelineRepository · SearchIndex          │
└───────────────────────────┬─────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  ai/          │   │  data/        │   │  capture/     │
│  Claude-      │   │  SQLite-      │   │  skærm, lyd   │
│  klient,      │   │  repositories,│   │  (genbruger   │
│  prompts,     │   │  migrationer, │   │  sampler +    │
│  værktøjer    │   │  FTS5-indeks  │   │  Swift-vision)│
└───────────────┘   └───────────────┘   └───────────────┘
```

Reglen fra GlemtDet holdes: **`domain/` importerer aldrig noget konkret.** Det
er dét, der gør AI-laget udskifteligt, og det er dét, der gør hele hukommelses-
løkken testbar uden netværk.

---

## 4. Database

Ét lokalt SQLite-arkiv i appens egen datamappe. Migration **v2** ovenpå
GlemtDets v1 — eksisterende installationer opgraderes uden datatab.

### Kerne

```sql
profile(id, display_name, grade_level, created_at, xp, level,
        gamification_enabled, onboarded_at)

subjects(id, name, color_token, icon, sort_order, archived)

topics(id, subject_id, name, first_seen, last_worked, mastery, ...)
        -- mastery: 0..1, opdateres af quizresultater og sessioner

notes(id, subject_id, topic_id, title, body_md, source, created_at,
      updated_at, pinned)
        -- source: 'manual' | 'ai' | 'live_notes' | 'import'

assignments(id, subject_id, title, description, due_at, estimated_minutes,
            completed_at, created_at)

conversations(id, title, created_at, updated_at)
messages(id, conversation_id, role, content, tokens, created_at,
         tool_calls_json)

quizzes(id, subject_id, topic_id, title, source_kind, source_ref, created_at)
quiz_questions(id, quiz_id, kind, prompt, options_json, answer, explanation,
               position)
        -- kind: 'multiple_choice' | 'true_false' | 'short_answer' | 'explain'
quiz_attempts(id, quiz_id, started_at, finished_at, score, total)
quiz_answers(id, attempt_id, question_id, given, correct, ai_feedback)

focus_sessions(id, subject_id, topic_id, assignment_id, started_at, ended_at,
               planned_minutes, actual_seconds, completed, notes)

timeline_events(id, kind, subject_id, ref_table, ref_id, title, summary,
                started_at, ended_at, source)
        -- kind: 'study' | 'quiz' | 'note' | 'chat' | 'focus' | 'break' | 'screen'

achievements(id, code, unlocked_at, progress)
daily_activity(day, minutes_studied, questions_answered, xp_earned, streak_day)
```

### Memory-systemet

```sql
memories(id, kind, key, value, confidence, source, subject_id,
         created_at, updated_at, last_used_at, use_count, pinned, active)
        -- kind: 'fact' | 'learning' | 'preference' | 'struggle' | 'strength'
        -- source: 'onboarding' | 'inferred' | 'quiz' | 'user_edit'

memory_links(memory_id, ref_table, ref_id)   -- hvor kom den fra
```

### Søgeindeks

```sql
CREATE VIRTUAL TABLE search_index USING fts5(
  title, body, tokenize='unicode61 remove_diacritics 2'
);
search_map(rowid, ref_table, ref_id, subject_id, occurred_at)
```

FTS5 giver rigtig fuldtekstsøgning på tværs af noter, samtaler, quizzer og
timeline. `remove_diacritics` klarer æøå. Findes FTS5 ikke i den bundtede
SQLite, falder søgningen tilbage på `LIKE` + `foldDanish()` + `fuzzy.dart` —
langsommere, men aldrig i stykker. Det verificeres ved opstart, ikke antages.

---

## 5. AI-integration

### Klientside med brugerens egen nøgle

Brugeren indsætter sin egen Anthropic API-nøgle under Indstillinger. Den gemmes
i **platformens sikre nøglelager** (Keychain / Credential Manager / Keystore) —
aldrig i SQLite, aldrig i en fil, aldrig i logs.

**Det ærlige forbehold, som også står i appen og i README:** en desktop-app
med brugerens egen nøgle betyder, at nøglen ligger på brugerens maskine, og at
kald går direkte fra maskinen til Anthropic. Det er fint til én bruger, og det
er ikke fint til en app, der distribueres til tusinde teenagere — der skal en
backend-proxy ind, som holder nøglen, laver auth og håndhæver rate limits.
`AiClient`-interfacet er skåret, så en `ProxyAiClient` kan tilføjes uden at
røre resten af appen. Den proxy er **ikke** en del af denne MVP.

### Abstraktionen

```dart
abstract class AiClient {
  String get id;                     // 'anthropic'
  String get modelLabel;
  bool get isConfigured;

  Stream<AiDelta> complete(AiRequest request);   // streaming
  Future<T> structured<T>(AiRequest request, AiSchema<T> schema);
  Future<AiHealth> check();
}
```

`AiRequest` bærer systemprompt, beskeder, valgfrie værktøjer og et
**memory-budget**. `structured()` bruger Claudes tool-use til at fremtvinge
gyldig JSON — det er sådan quizzer, noter og memory-udtræk genereres, ikke ved
at bede om JSON i prosa og håbe.

`lib/ai/ai_stack.dart` bliver det ene sted, der nævner en konkret udbyder —
samme mønster som `vision_stack.dart`. Uden nøgle returneres en
`UnconfiguredAiClient`, der får UI'et til at vise en rolig opfordring til at
tilføje en nøgle i stedet for at fejle.

### Værktøjer AI'en får

`search_notes` · `get_subject_status` · `create_note` · `create_quiz` ·
`remember` · `get_schedule` · `log_activity`

Det er dét, der gør TeenBrain til andet end en chatklient: AI'en kan slå op i
brugerens egne data og skrive tilbage til hukommelsen.

---

## 6. Memory-systemet

Den vigtigste funktion. Tre dele:

**1. Optagelse.** Memories skrives fra fire kilder: onboarding (eksplicit),
quizresultater (målt — "fejler konsekvent andengradsligninger"), AI-inferens
(efter en samtale kører en billig strukturerings-prompt, der foreslår memories)
og brugerens egne redigeringer.

**2. Hentning — det skalerbare stykke.** Hele databasen sendes aldrig med. Ved
hver forespørgsel bygges en kontekstpakke under et fast token-budget:

```
altid med:      profil (navn, klassetrin, fag)            ~150 tokens
altid med:      aktive præferencer                        ~200 tokens
relevans:       memories der matcher forespørgslen        ~600 tokens
tidslig:        seneste aktivitet, åbne deadlines         ~400 tokens
fag-scoped:     når et fag er i fokus, dets svagheder     ~400 tokens
```

Relevansen scores lokalt uden ekstra AI-kald: FTS5-match + fag-overlap +
nyhedsværdi + `use_count`. Rækkefølgen er `score DESC`, og der skæres ved
budgettet. Det holder omkostningen konstant, uanset om brugeren har 20 eller
20.000 memories.

**3. Kontrol.** Hver memory har `active`. Slås en fra, forlader den
kontekstpakken øjeblikkeligt — den slettes ikke, men den bruges ikke. Siden
*My AI* viser hver eneste memory, hvor den kom fra (`memory_links`), og lader
brugeren rette, slå fra eller slette.

---

## 7. Screen Understanding

Den mest privacy-følsomme funktion, og derfor den mest konservativt byggede.

**Opt-in, aldrig som standard.** Slået fra ved installation. Kræver et aktivt
valg med en skærm, der forklarer præcis hvad der sker.

**Synligt når aktiv.** Rød prik i titelbjælken og i sidebaren, hele tiden —
samme `_RecordingDot` GlemtDet allerede bruger.

**Intet gemmes som standard.** Skærmbilledet analyseres i hukommelsen og
kasseres. Kun *konklusionen* — "fag: matematik, emne: andengradsligninger" —
kan gemmes, og kun hvis brugeren har slået det til.

**Kadencen genbruges.** `IntelligentSampler` fra GlemtDet: aldrig hurtigere end
1,2 s, kun ved scene-ændring, eksponentiel backoff op til 40 s når der ikke
sker noget. Det gør funktionen billig nok til at have kørende.

**macOS:** ny `ScreenCaptureController.swift` med ScreenCaptureKit ved siden af
den eksisterende `CameraController.swift`, plus `VNRecognizeTextRequest` i
`VisionAnalyzer.swift` til at læse tekst på skærmen lokalt. macOS' egen
skærmoptagelses-indikator lyser — den kan ikke skjules, og det er en feature.

**Windows:** ikke bygget i denne omgang. `ScreenStack.forCurrentPlatform()`
returnerer en `UnavailableScreenReader`, der siger det ligeud i UI'et i stedet
for at vise en tom firkant. Præcis som GlemtDet gør med kameraet i dag.

---

## 8. Live Notes (transskription)

**Fase 2, efter MVP.** Planen står her, så arkitekturen kan bære den.

Mikrofonoptagelse med `record` → chunks → transskription → strukturering til
noter med `structured()`.

Transskriptionen sker bag et `Transcriber`-interface med to tænkte
implementeringer: Apples on-device `SFSpeechRecognizer` (gratis, offline,
udmærket dansk) og en cloud-mulighed. On-device er standarden.

**Indtil den er bygget:** Live Notes-siden findes, forklarer hvad den vil kunne,
og er tydeligt markeret *Kommer snart*. Der bygges ikke en falsk knap, der
lader som om den optager. Til gengæld virker *indsæt en transskription eller
tekst og få den struktureret som noter* fra MVP'en — det er den halvdel, der
kan bygges ærligt nu.

---

## 9. Authentication

**MVP har ingen konto og intet login.** Appen er single-user og lokal. "Login"
i briefet dækkes af onboarding, der etablerer en profil på enheden.

Det er ikke sjusk, det er rækkefølge: en konto uden en server at logge ind på
er teater. Skemaet er forberedt (`profile` har et id, alt fremmednøgler til
det), så synkronisering kan tilføjes uden en migrering, der gør ondt.

Valgfri app-lås med systemets biometri kan tilføjes senere.

---

## 10. Privacy

Arvet holdning fra GlemtDet: **appen kan ikke gøre noget, brugeren ikke har
slået til.**

* Alt ligger i appens egen datamappe. På macOS under App Sandbox:
  `~/Library/Containers/dk.teenbrain.app/Data/Library/Application Support/`
* API-nøglen ligger i Keychain, ikke i databasen.
* **Netværksadgang tilføjes** (`com.apple.security.network.client`) — det er en
  reel ændring fra GlemtDet, som ikke havde den. Den er nødvendig for at tale
  med Claude, og det skal stå tydeligt i UI'et: **det du skriver i chatten,
  sendes til Anthropic.** Alt andet — noter, quizzer, timeline, memories —
  bliver på maskinen, medmindre det udvælges som kontekst til en forespørgsel.
* Mikrofon og skærmoptagelse: separate entitlements, begge slået fra som
  standard, begge med synlig indikator når aktive.
* Privacy-siden viser hver kontakt: skærm, mikrofon, kamera, AI-hukommelse,
  automatiske noter, opbevaringsperiode, slet alt.
* Databehandling-sektionen viser i klartekst, hvad der forlader enheden og
  hvad der ikke gør. Ingen jura, almindeligt dansk.

---

## 11. Design

Ét accentfarve, meget hvidt, type der ikke råber. Fundamentet ligger i
`theme.dart` og udvides:

* **Radier op.** 12 → 16 på kort, 8 → 10 på knapper. Blødere, mere 2026.
* **Skygger tilføjes.** GlemtDet bruger kun hairline-borders. TeenBrain får
  meget lette skygger på løftede kort — `blur 20, y 4, alpha 0.04`.
* **Typografi.** Samme skala, større displaystørrelse på forsiden.
  "Godmorgen, Marcus" skal fylde.
* **Bevægelse.** 110–160 ms, `easeOut`. Sideskift krydsfader.
* **Farver:** blå accent + fire semantiske toner. Fag får hver sin farve fra et
  behersket sæt på seks.
* **Layout:** sidebar over 700 px, bottom navigation under. Samme sider, samme
  providers — kun stellet skifter.

---

## 12. Rækkefølge

Hvert trin bygges, testes og kompileres før det næste.

| # | Trin | Status |
|---|---|---|
| 1 | Fundament — afhængigheder, skema v2, mobil-stier, tema | ✅ |
| 2 | Domænelag — 10 modeller, 11 interfaces | ✅ |
| 3 | Datalag — SQLite-repositories, FTS5-indeks | ✅ 49 tests |
| 4 | AI-lag — `AiClient`, Anthropic-klient, streaming, `structured()` | ✅ |
| 5 | Memory — optagelse, relevans, kontekstbygger | ✅ 31 tests |
| 6 | Shell — responsiv sidebar/bottom-nav, ruter | ✅ |
| 7 | Onboarding — 6 trin, skriver profil + første memories | ✅ |
| 8 | Forside — hilsen, AI-forslag, inputboks | ✅ |
| 9 | Chat — streaming, værktøjer, historik | ✅ |
| 10 | Noter — CRUD, markdown, AI-strukturering | ✅ |
| 11 | Fag — emner, mastery, opgaver, deadlines | ✅ |
| 12 | Quiz — generering, fire typer, retning, fejl → memory | ✅ |
| 13 | Focus — timer, minimal UI, opsamling | ✅ |
| 14 | Timeline — dagsgruppering, klikbare rækker | ✅ |
| 15 | Søgning — FTS5 + LIKE + fuzzy, lokal fortolkning | ✅ |
| 16 | My AI — vis, rediger, slet, slå fra, se kontekstpakken | ✅ |
| 17 | Privacy — alle kontakter, eksport, sletning | ✅ |
| 18 | Gamification — XP, streak, level, achievements | ✅ |
| 19 | Screen Understanding | ⬜ kun samtykkeside |
| 21 | Live Notes — optagelse og transskription | ⚠️ typetjekket, aldrig kørt |
| 20 | Oprydning — testsuite, build, README | ✅ 229 tests |

Fase 2, ikke bygget: ScreenCaptureKit, Windows-skærmlæsning, mobil-builds,
læringsanalyse.

Live Notes-optagelsen er skrevet efter planens afsnit 8 — `SFSpeechRecognizer`
på enheden, bag et `Transcriber`-interface — men Xcode forsvandt fra maskinen
undervejs. Swift-laget typetjekker med `swiftc` fra Command Line Tools, men
appen kan ikke bygges, så koden har aldrig kørt. Dart-siden er testet med en
fake genkender.

---

## 13. Løfter om ærlighed

Fra GlemtDets README, og de gælder stadig:

1. **Ingen falsk funktionalitet.** Kan noget ikke bygges ordentligt nu, står der
   *Kommer snart* med en forklaring — ikke en knap, der lader som om.
2. **Ingen døde knapper.** Alt klikbart gør noget eller siger hvorfor ikke.
3. **Blinde vinkler dokumenteres.** Som GlemtDet skriver, at Apple Vision ikke
   kan se nøgler, skriver TeenBrain, hvad den ikke ved.
4. **Tests er ikke pynt.** Hvert lag testes; de 95 eksisterende tests skal blive
   ved med at passe.

### Kendte begrænsninger i denne MVP

| Begrænsning | Hvorfor |
|---|---|
| Ingen konto, ingen sky-sync | Ingen backend i MVP. Skemaet er forberedt. |
| Brugerens egen API-nøgle | Ingen proxy at holde en delt nøgle i. Ikke egnet til distribution til rigtige teenagere. |
| Live Notes uden mikrofon | Transskription er fase 2. Tekst-til-noter virker. |
| Screen Understanding kun macOS | ScreenCaptureKit er macOS. Windows siger det ligeud. |
| Ingen mobil-build endnu | Koden er klar; iOS/Android-mapper skal genereres og testes. |

---

## 14. Hvor implementeringen afveg fra planen

Fire steder viste virkeligheden noget, planen ikke vidste:

**Nøglelageret blev native i stedet for en plugin.** Planen sagde
`flutter_secure_storage`. Den pakke kræver CocoaPods, og dette projekt har
bevidst ingen CocoaPods-integration — et macOS-build er `flutter build` og
ingenting andet. Firs linjers Swift mod Keychain direkte
(`macos/Runner/GlemtDet/SecretStore.swift`, hængt på den eksisterende
`dk.glemtdet/system`-kanal) var den bedre handel. Windows fik en
adgangsbegrænset fil som fallback, og appen siger det selv.

**`temperature` findes ikke længere.** Planens `AiRequest` havde en
temperature-parameter. De aktuelle Claude-modeller afviser sampling-parametre
med en 400-fejl; `output_config.effort` er knappen, der reelt handler kvalitet
mod ventetid. Interfacet blev rettet, før den første forespørgsel blev sendt.

**Søgningen fik et tredje lag.** Planen havde FTS5 med `LIKE` som fallback.
Ingen af dem finder `brøker` for en, der skriver `broker` — foldningen giver
`broeker` mod `broker`, ét bogstav fra hinanden. Der er nu en fuzzy-scanning,
der kun kører, når de to hurtige veje kom tomme tilbage.

**Ikonografien holdt ikke.** Både GlemtDet og den første version af TeenBrain
brugte Unicode-glyffer (`◈`, `⌕`, `▦`) som ikoner. Et golden-render afslørede,
at de tegner sig som tomme firkanter, så snart systemets skrifttype ikke
tilfældigvis har dem. Alt i TeenBrains navigation og knapper bruger nu
Material-ikoner, som er bundtet med appen.

---
