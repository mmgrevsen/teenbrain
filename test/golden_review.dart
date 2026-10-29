/// Renders pages to PNG so the design can be looked at, not just asserted.
///
/// **Not part of `flutter test`.** The filename deliberately does not end in
/// `_test.dart`, so the default run skips it. These images contain wall-clock
/// text ("Sidst kl. 16:50") and a weekday strip, so they drift by the minute
/// and by the day — as a blocking regression test they would fail for reasons
/// that have nothing to do with the code. As a design-review tool they are
/// worth keeping: the first run of them caught two real bugs, tofu icons and
/// short pages floating in the middle of the window.
///
/// Run them by hand:
///
///   flutter test test/golden_review.dart --update-goldens
///
///
/// `flutter test` normally substitutes a font whose glyphs are all squares,
/// which makes an image useless as design review. This loads the real system
/// UI font from disk first, so the output is close to what the app actually
/// draws. That file only exists on macOS, so the whole suite skips elsewhere.
///
/// The images land in `test/goldens/`.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/app/navigation.dart';
import 'package:glemtdet/features/shell/app_shell.dart';

import 'ui_test.dart' as harness;

const _systemFont = '/System/Library/Fonts/SFNS.ttf';

/// Written by the build into `build/unit_test_assets/`. Without it every
/// `Icon` renders as an empty box — which is how the first run of these
/// goldens revealed that the app was still drawing Unicode glyphs.
const _iconFont = 'build/unit_test_assets/fonts/MaterialIcons-Regular.otf';

Future<void> _load(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _loadFonts() async {
  await _load('SF', _systemFont);
  await _load('MaterialIcons', _iconFont);
}

void main() {
  // Both fonts have to be there, or every glyph renders as a box and the
  // comparison fails for a reason that has nothing to do with the app. The
  // icon font is written by the build, so a clean checkout needs one
  // `flutter test` before these can run.
  if (!Platform.isMacOS ||
      !File(_systemFont).existsSync() ||
      !File(_iconFont).existsSync()) {
    test(
      'goldens kræver macOS, systemets skrifttype og et build først',
      () {},
      skip: 'Kør `flutter test` én gang, og kør så disse på macOS.',
    );
    return;
  }

  setUpAll(_loadFonts);

  Future<void> shoot(
    WidgetTester tester,
    String name,
    AppRoute route, {
    Brightness brightness = Brightness.light,
    Size size = const Size(1200, 860),
    bool seeded = true,
  }) async {
    await harness.pumpRoute(
      tester,
      route,
      size: size,
      seed: seeded ? harness.seedRealistic : null,
      brightness: brightness,
      fontFamily: 'SF',
    );
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/$name.png'),
    );
    harness.tearDownDb();
  }

  testWidgets('forside', (t) => shoot(t, '01-forside', const HomeRoute()));
  testWidgets('fag', (t) => shoot(t, '02-fag', const SubjectsRoute()));
  testWidgets('fag-detalje', (t) => shoot(t, '03-fag-detalje', const SubjectDetailRoute(1)));
  testWidgets('noter', (t) => shoot(t, '04-noter', const NotesRoute()));
  testWidgets('note', (t) => shoot(t, '05-note', const NoteDetailRoute(1)));
  testWidgets('quiz', (t) => shoot(t, '06-quiz', const QuizzesRoute()));
  testWidgets('quiz-resultat', (t) =>
      shoot(t, '07-quiz-resultat', const QuizResultRoute(quizId: 1, attemptId: 1)));
  testWidgets('fokus', (t) => shoot(t, '08-fokus', const FocusRoute()));
  testWidgets('timeline', (t) => shoot(t, '09-timeline', const TimelineRoute()));
  testWidgets('min ai', (t) => shoot(t, '10-min-ai', const MyAiRoute()));
  testWidgets('privatliv', (t) => shoot(t, '11-privatliv', const PrivacyRoute()));
  testWidgets('indstillinger', (t) => shoot(t, '12-indstillinger', const SettingsRoute()));
  testWidgets('chat', (t) => shoot(t, '13-chat', const ChatRoute()));
  testWidgets('søgning', (t) => shoot(t, '14-soegning', const SearchRoute()));
  testWidgets('live notes', (t) => shoot(t, '19-live-notes', const LiveNotesRoute()));

  testWidgets('forside mørk', (t) => shoot(
        t, '15-forside-moerk', const HomeRoute(), brightness: Brightness.dark,
      ));
  testWidgets('fag mørk', (t) => shoot(
        t, '16-fag-moerk', const SubjectsRoute(), brightness: Brightness.dark,
      ));

  testWidgets('forside telefon', (t) => shoot(
        t, '17-forside-telefon', const HomeRoute(), size: const Size(390, 844),
      ));
  testWidgets('fag telefon', (t) => shoot(
        t, '18-fag-telefon', const SubjectsRoute(), size: const Size(390, 844),
      ));
}
