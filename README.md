# TeenBrain

En personlig AI-"second brain" til teenagere på 13–18 år. TeenBrain husker ting
for dig og lærer, hvordan du fungerer — og bruger det til at hjælpe med skole,
noter, lektier, planlægning og træning.

Det er ikke en chatklient med en database ved siden af. Hukommelsen er
produktet; chatten er én af flere måder at komme til den på.

macOS i dag. Windows kompilerer. iPhone og Android er forberedt, ikke bygget.

---

## Sådan kører du den

Kræver Flutter 3.47 eller nyere.

```bash
flutter pub get
flutter test          # 252 tests
flutter run -d macos
```

Byg en app du kan installere:

```bash
flutter build macos --release
# resultatet: build/macos/Build/Products/Release/TeenBrain.app
```

Første gang appen åbner, spørger den om dit navn, klassetrin og fag. Det tager
et halvt minut, og alt kan rettes bagefter under Indstillinger.

### For at AI'en virker

TeenBrain bruger **din egen Anthropic API-nøgle**. Uden den virker alt det
lokale — noter, fag, quizzer du allerede har, timeline, søgning, fokus — men
chatten, quiz-generering og forslagene på forsiden gør ikke.

1. Hent en nøgle på [console.anthropic.com](https://console.anthropic.com) →
   Settings → API keys.
2. Åbn TeenBrain → Indstillinger → Anthropic API-nøgle → indsæt og gem.

Nøglen gemmes i macOS' **Keychain**, ikke i appens database. Appen tester den
med det samme og siger til, hvis den bliver afvist.

**Det ærlige forbehold:** en app med brugerens egen nøgle er fin til én person.
Skal TeenBrain deles ud til rigtige teenagere, skal nøglen ligge på en server,
der håndterer auth og rate limits. `AiClient`-interfacet er skåret, så en
`ProxyAiClient` kan tilføjes uden at røre resten af appen. Den proxy er ikke
bygget.

---

## Hvad der faktisk virker, og hvad der ikke gør

Den ærlige liste. Intet i appen foregiver at kunne noget, den ikke kan.

| | macOS | Windows | iOS / Android |
|---|---|---|---|
| Onboarding, profil | ✅ | ✅ | ⬜ ikke bygget |
| Dashboard med AI-forslag | ✅ | ✅ | ⬜ |
| AI-chat med streaming og værktøjer | ✅ | ✅ | ⬜ |
| Memory-system | ✅ | ✅ | ⬜ |
| Noter (skriv, AI-strukturér, markdown) | ✅ | ✅ | ⬜ |
| Fag, emner, mastery, opgaver | ✅ | ✅ | ⬜ |
| Quiz-generator, fire spørgsmålstyper | ✅ | ✅ | ⬜ |
| Focus mode | ✅ | ✅ | ⬜ |
| Timeline | ✅ | ✅ | ⬜ |
| Global søgning (FTS5 + fuzzy) | ✅ | ✅ | ⬜ |
| Min AI — se, ret, slå fra, slet | ✅ | ✅ | ⬜ |
| Privacy-kontroller, eksport, sletning | ✅ | ✅ | ⬜ |
| Gamification (XP, streak, level) | ✅ | ✅ | ⬜ |
| API-nøgle i systemets nøglering | ✅ Keychain | ⚠️ fil-fallback | ⬜ |
| Live Notes — tekst ind, noter ud | ✅ | ✅ | ⬜ |
| Live Notes — mikrofon og transskription | ⚠️ typetjekket, aldrig kørt | ❌ | ❌ |
| Screen Understanding | ❌ ikke bygget | ❌ | — |

**Mobil.** Koden er klar: `AppPaths.resolveDataDirectory()` bruger
`path_provider` på iOS og Android, layoutet skifter til bundnavigation under
700 px, og UI-testene kører hver side i 390×844. Men `ios/` og `android/`-
mapperne er ikke genereret, og intet er bygget eller kørt på en telefon. Det er
ærligt talt forskellen mellem "forberedt" og "virker".

**Nøglelagring på Windows.** macOS bruger Keychain gennem appens eget native lag
(`macos/Runner/GlemtDet/SecretStore.swift`). Windows falder tilbage på en
adgangsbegrænset fil i appens datamappe. Det er ikke lige så godt som Credential
Manager, og appen skriver det selv på Indstillinger-siden i stedet for at lade
brugeren tro noget andet.

**Live Notes.** Tekst ind og strukturerede noter ud virker og er testet.

Optagelsen er nu også skrevet: `AVAudioEngine` plus Apples `SFSpeechRecognizer`
med `requiresOnDeviceRecognition = true`, så lyden aldrig forlader maskinen.
Kan dansk ikke genkendes lokalt på en given Mac, nægter den at starte frem for
at falde tilbage på Apples servere — fordi det stille ville bryde løftet på
Privatliv-siden.

**Men den er aldrig kørt.** Xcode er ikke installeret på udviklingsmaskinen, så
appen kan ikke bygges, og det native lag har aldrig udført en eneste instruktion.

Det er til gengæld typetjekket. Command Line Tools indeholder `swiftc`, selv om
`xcodebuild` mangler, så hele Swift-modulet kan kontrolleres uden Xcode:

```bash
swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" \
  -target arm64-apple-macosx10.15 \
  -F build/macos/Build/Products/Release \
  macos/Runner/GlemtDet/*.swift
```

Det går rent. Syntaks, typer og alle kald til `AVAudioEngine`,
`SFSpeechRecognizer` og Flutters protokoller er altså korrekte, og plugin'ets
referencer til de nye klasser hænger sammen. Det er ikke det samme som at det
virker — om lyd-tappet faktisk leverer buffere, om denne Mac overhovedet kan
genkende dansk lokalt, og om tilladelsesforløbet opfører sig som tænkt, kan kun
en kørsel vise.

Dart-siden er derimod testet: 22 tests med en fake genkender dækker de to
tilladelser, forskellen på en revideret og en færdig sætning, en genkender der
selv giver op, at allerede hørt tekst ikke går tabt ved en fejl, og reglen om at
intet optager med mikrofonen slået fra.

Rækkefølgen er med vilje: en optagelse lander altid i editoren, så fagord kan
rettes, før teksten bliver til en note. "Automatiske noter" på Privatliv-siden
er stadig slået fra og markeret som ikke bygget.

**Screen Understanding.** Der er en samtykkeside, der forklarer præcis hvad
funktionen ville gøre og hvilke regler den ville følge — men selve
skærmoptagelsen er ikke skrevet. Kontakten på Privatliv-siden fører til den
side i stedet for at slå noget til, der ikke findes.

---

## Hvad der forlader din computer

Det her er det spørgsmål, en privacy-side normalt er vag omkring, så det står
også i appen:

* **Sendes til Anthropic:** det du skriver i chatten, plus de relevante stumper
  hukommelse og noter, som appen vælger at sende med. Du kan se præcis hvad,
  under **Min AI → Hvad jeg sender med**.
* **Bliver på maskinen:** alt andet. Noter, quizzer, resultater, timeline,
  hukommelse og indstillinger ligger i én SQLite-fil i appens egen datamappe.
* **Sendes aldrig:** lyd. Live Notes genkender tale lokalt og nægter at starte,
  hvis den ikke kan. Lyden gemmes heller ikke — der er kun tekst undervejs, og
  derfor ingen buffer at slette bagefter. Derudover er der ingen analytics,
  ingen crash-rapportering og ingen konto.

Alt der kan observere dig — skærm, mikrofon, kamera — er slået **fra** ved
installation. AI-hukommelsen er slået til, men den observerer ikke af sig selv:
den husker kun det, du allerede har skrevet, og hver eneste linje står på
Min AI-siden med hvor den kom fra.

Under App Sandbox ligger data i
`~/Library/Containers/dk.glemtdet.app/Data/Library/Application Support/GlemtDet`.

---

## Arkitektur

```
features/            én mappe pr. side, kun UI
      │
      ▼  Riverpod providers (app/providers.dart)
domain/              modeller + interfaces
                     ved intet om Anthropic, SQLite eller Flutter
      │
      ├──► ai/       Claude-klient, prompts, værktøjer, nøglelager
      ├──► brain/    kontekstbygger, skemaer, søgefortolkning
      └──► data/     SQLite-repositories, migrationer, FTS5-indeks
```

Reglen: **`domain/` importerer aldrig noget konkret.** Det er dét, der gør
AI-laget udskifteligt, og dét, der gør hele hukommelsesløkken testbar uden
netværk.

* `lib/domain/` — modeller og de interfaces, resten af appen programmerer imod.
* `lib/data/` — SQLite-skema, migrationer, repositories, søgeindeks.
* `lib/ai/` — det ene sted, der nævner Anthropic.
* `lib/transcription/` — det ene sted, der nævner Apples talegenkendelse.
* `lib/brain/` — hukommelse, prompts, værktøjer, struktureret output.
* `lib/features/` — én mappe pr. side.
* `macos/Runner/GlemtDet/` — det native Swift-lag: Keychain, kamera, Vision,
  talegenkendelse.

### At skifte AI-model ud

`lib/ai/ai_stack.dart` er det eneste sted, der nævner en konkret udbyder — samme
mønster som `vision_stack.dart` bruger til computer vision. En ny model kræver
én klasse, der implementerer `AiClient`, plus en gren i `AiStack.forKey()`.
Resten af appen mærker det ikke. Uden nøgle returneres en
`UnconfiguredAiClient`, der fejler ét forudsigeligt sted med én sætning, UI'et
kan vise — det er dét, der gør, at hver skærm kan kalde AI'en uden først at
tjekke, om der er en.

### Memory-systemet

Den vigtigste funktion, og den mest misforståede. Hele databasen sendes aldrig
med. Ved hver forespørgsel bygger `ContextBuilder` en pakke under et fast
token-budget:

```
altid med:   profil (navn, klassetrin, fag)         ~150 tokens
altid med:   præferencer — hvordan du bedst lærer   ~200 tokens
relevans:    memories der matcher spørgsmålet       ~600 tokens
tidslig:     seneste aktivitet, åbne deadlines      ~400 tokens
fag-scoped:  når et fag er i fokus, dets svagheder  ~400 tokens
```

Relevansen scores **lokalt** — FTS5-match, fag-overlap, nyhedsværdi,
brugsfrekvens — uden et ekstra modelkald. Det gør kontekstbygning gratis og
holder omkostningen konstant, uanset om du har 20 eller 20.000 memories. Der er
en test, der beviser det: databasen vokser til 400 memories, og kontekstpakken
vokser ikke.

Hver memory har en `active`-kontakt. Slås den fra, forlader den kontekstpakken
øjeblikkeligt — rækken bliver, men den bruges ikke. Og hver memory ved, hvor
den kom fra, så Min AI-siden kan vise sine kilder.

### Database

Ét lokalt SQLite-arkiv. Skemaet er versioneret: **v1 er GlemtDets** visuelle
hukommelse, **v2 er TeenBrain**. De deler fil og forbindelse, men ikke en eneste
tabel, så en eksisterende GlemtDet-installation opgraderer på stedet uden at
miste noget.

Søgning bruger FTS5 når den bundtede SQLite har det — verificeret ved opstart,
ikke antaget. Har den ikke, falder søgningen tilbage på foldet tekst med `LIKE`.
Og finder ingen af dem noget, kører en fuzzy-scanning, så `broker` stadig finder
`brøker`. Langsommere, aldrig i stykker.

---

## Om GlemtDet

Det her projekt begyndte som **GlemtDet** — en lokal visuel hukommelse, der
genkendte ting med kameraet og svarede på *"hvor lagde jeg mine AirPods?"*.

TeenBrain overtog appen, men GlemtDet blev ikke smidt væk. Dens infrastruktur
er fundamentet her: temaet, database-laget, de delte widgets, den danske
tids- og grammatikhåndtering, fuzzy-søgningen, sampler-logikken og hele det
native Swift-lag. Dens **produktsider** — Scanner, Objekter, kamera-hukommelsen —
er ude af navigationen, men filerne ligger stadig i repoet, de kompilerer, og
deres 95 tests kører stadig. At hente kamera-hukommelsen frem igen er ét
navigationspunkt fra at være muligt.

Derfor hedder bundle-id'et stadig `dk.glemtdet.app`, og datamappen hedder stadig
`GlemtDet`. Under App Sandbox bestemmer bundle-id'et container-stien, og den
container holder databasen, som skema v2 migrerer på stedet. Et nyt id ville
starte en tom app ved siden af de gamle data. Skift det kun sammen med et
migrerings-trin.

---

## Test

```bash
flutter test                                    # 252, uden hardware
flutter test test/golden_review.dart --update-goldens   # designbilleder, macOS
flutter test integration_test/vision_backend_test.dart -d macos   # med kamera
```

**252 tests**, fordelt sådan:

* **95** fra GlemtDet — taksonomi mod Apple Visions rigtige ordforråd,
  sampler-adfærd, de-duplikering, SQLite-laget, dansk tid og grammatik.
* **49** på TeenBrains datalag — migration, profil, fag, mastery-glidning,
  quiz-scoring, streaks, achievements, og hele søgeindekset inklusive
  FTS5-tilstedeværelse og æøå.
* **31** på hjernelaget — søgefortolkning, skema-parsing (inklusive at en
  multiple choice uden facit blandt mulighederne bliver *repareret*),
  kontekstbudget, og hvad et quizresultat lærer systemet.
* **22** på Live Notes — de to tilladelser, revision mod færdig sætning, en
  genkender der stopper af sig selv, og privacy-kontakten.
* **55** på UI'et — hver eneste side renderet mod en rigtig database, tom og
  fyldt, på desktop og i 390×844, plus detaljesider og ikke-fundne id'er.

UI-testene fangede rigtige fejl undervejs: sider der flød over på telefon,
detaljesider der viste en skeleton i det uendelige for en slettet note, og en
`AnimatedSwitcher`, der centrerede korte sider midt i vinduet.

### Designbilleder

`test/golden_review.dart` renderer siderne til PNG i `test/goldens/`. Det er
**ikke** en del af `flutter test` — billederne indeholder klokkeslæt og en
ugestribe, så de driver fra minut til minut og ville fejle af grunde, der intet
har med koden at gøre. Som designværktøj er de til gengæld gode: første kørsel
afslørede, at hele appens ikonografi var Unicode-glyffer, der tegnede sig som
tomme firkanter.

---

## Kendte begrænsninger

| Begrænsning | Hvorfor |
|---|---|
| Ingen konto, ingen sky-synkronisering | Der er ingen backend. Skemaet er forberedt: `profile` har et id, og alt peger på det. |
| Brugerens egen API-nøgle | Ingen proxy at holde en delt nøgle i. Ikke egnet til distribution. |
| Live Notes-optagelse er aldrig kørt | Swift-laget typetjekker, men Xcode mangler, så appen kan ikke bygges og koden har aldrig udført noget. |
| Screen Understanding kun som samtykkeside | ScreenCaptureKit-laget er ikke skrevet. |
| Ingen mobil-build | Koden er klar, mapperne er ikke genereret, intet er kørt på en telefon. |
| Windows-nøglelager er en fil | Credential Manager kræver et native lag, der ikke er skrevet. |
| Ingen i18n | UI'et er dansk. Teksterne ligger i widgets, ikke i en ressourcefil. |

---

## Hjælpescript

`tool/add_native_sources.dart` registrerer de håndskrevne Swift-filer i
Xcode-projektet. Den læser filerne fra disken i stedet for en fast liste — en
fast liste bliver forældet i det øjeblik nogen tilføjer en `.swift`-fil, og
fejlen er en fil, der stille aldrig bliver bygget. Kør den efter at have
tilføjet native kode; den er en no-op, hvis alt allerede er registreret.
