/// The app's iconography.
///
/// Material icons rather than Unicode glyphs. A glyph like `◈` or `⌕` depends
/// on the system font happening to contain it, and the fallback is a hollow
/// box — which is exactly what a golden render caught. Material icons ship
/// inside the app (`uses-material-design: true`), so they draw the same on
/// every platform.
///
/// One outline weight throughout, so nothing shouts.
library;

import 'package:flutter/material.dart';

import '../../domain/models/timeline.dart';

class AppIcons {
  const AppIcons._();

  // Navigation
  static const home = Icons.cottage_outlined;
  static const chat = Icons.chat_bubble_outline_rounded;
  static const subjects = Icons.menu_book_outlined;
  static const notes = Icons.description_outlined;
  static const quiz = Icons.checklist_rounded;
  static const timeline = Icons.schedule_outlined;
  static const myAi = Icons.auto_awesome_outlined;
  static const privacy = Icons.shield_outlined;
  static const settings = Icons.settings_outlined;
  static const search = Icons.search_rounded;
  static const more = Icons.more_horiz_rounded;

  // Actions
  static const back = Icons.chevron_left_rounded;
  static const forward = Icons.chevron_right_rounded;
  static const expand = Icons.expand_more_rounded;
  static const focus = Icons.timer_outlined;
  static const newNote = Icons.post_add_rounded;
  static const pinned = Icons.push_pin_rounded;
  static const check = Icons.check_rounded;
  static const liveNotes = Icons.graphic_eq_rounded;

  /// A timeline row's icon. Lives here rather than on [TimelineKind] because
  /// `domain/` does not import Flutter — that rule is what keeps the model
  /// layer testable without a widget binding.
  static IconData forTimeline(TimelineKind kind) => switch (kind) {
        TimelineKind.study => Icons.school_outlined,
        TimelineKind.quiz => Icons.checklist_rounded,
        TimelineKind.note => Icons.description_outlined,
        TimelineKind.chat => Icons.chat_bubble_outline_rounded,
        TimelineKind.focus => Icons.timer_outlined,
        TimelineKind.breakTime => Icons.pause_circle_outline_rounded,
        TimelineKind.screen => Icons.desktop_windows_outlined,
      };
}
