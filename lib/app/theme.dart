/// GlemtDet's visual language.
///
/// One accent colour, a lot of whitespace, and type that gets out of the way —
/// the app should feel like a native macOS utility, not a web page in a window.
/// Colours are defined once as a token set and resolved per brightness, so a
/// widget never reaches for a raw hex value.
library;

import 'package:flutter/material.dart';

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.canvas,
    required this.sidebar,
    required this.surface,
    required this.surfaceHover,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.accentText,
    required this.positive,
    required this.warning,
    required this.danger,
    required this.recording,
    required this.subjectPalette,
    required this.elevation,
  });

  final Color canvas;
  final Color sidebar;
  final Color surface;
  final Color surfaceHover;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentSoft;
  final Color accentText;
  final Color positive;
  final Color warning;
  final Color danger;
  final Color recording;

  /// Six subject colours, resolved per brightness. A subject stores a token
  /// name, never a hex value, so it looks right in both themes.
  final Map<String, Color> subjectPalette;

  /// The one shadow the app uses. Barely there on purpose: the surface reads as
  /// lifted, not as a floating box.
  final List<BoxShadow> elevation;

  Color subject(String token) => subjectPalette[token] ?? accent;

  static const light = AppColors(
    canvas: Color(0xFFFCFCFD),
    sidebar: Color(0xFFF6F6F7),
    surface: Color(0xFFFFFFFF),
    surfaceHover: Color(0xFFF1F1F3),
    border: Color(0xFFE7E7EA),
    borderStrong: Color(0xFFD5D5DA),
    textPrimary: Color(0xFF16171A),
    textSecondary: Color(0xFF5F6169),
    textTertiary: Color(0xFF9A9CA5),
    accent: Color(0xFF3B6CF6),
    accentSoft: Color(0xFFEDF1FE),
    accentText: Color(0xFFFFFFFF),
    positive: Color(0xFF1E9E5A),
    warning: Color(0xFFB4761B),
    danger: Color(0xFFD03B3B),
    recording: Color(0xFFE0453C),
    subjectPalette: {
      'blue': Color(0xFF3B6CF6),
      'violet': Color(0xFF7C5CF0),
      'teal': Color(0xFF0E9B8E),
      'amber': Color(0xFFC07A12),
      'rose': Color(0xFFD6456F),
      'green': Color(0xFF1E9E5A),
    },
    elevation: [
      BoxShadow(color: Color(0x0A101828), blurRadius: 20, offset: Offset(0, 4)),
      BoxShadow(color: Color(0x08101828), blurRadius: 3, offset: Offset(0, 1)),
    ],
  );

  static const dark = AppColors(
    canvas: Color(0xFF141416),
    sidebar: Color(0xFF19191C),
    surface: Color(0xFF1E1E22),
    surfaceHover: Color(0xFF27272C),
    border: Color(0xFF2B2B31),
    borderStrong: Color(0xFF3A3A42),
    textPrimary: Color(0xFFF2F2F4),
    textSecondary: Color(0xFFA6A7B0),
    textTertiary: Color(0xFF6E6F79),
    accent: Color(0xFF6E8FFF),
    accentSoft: Color(0xFF23283C),
    accentText: Color(0xFF0C0C0E),
    positive: Color(0xFF44C583),
    warning: Color(0xFFD9A441),
    danger: Color(0xFFF06A6A),
    recording: Color(0xFFFF5F55),
    subjectPalette: {
      'blue': Color(0xFF6E8FFF),
      'violet': Color(0xFF9E85FF),
      'teal': Color(0xFF3FC0B0),
      'amber': Color(0xFFE0A94A),
      'rose': Color(0xFFF06A93),
      'green': Color(0xFF44C583),
    },
    // Shadows do almost nothing on a dark ground; the border carries the edge.
    elevation: [
      BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 4)),
    ],
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      recording: Color.lerp(recording, other.recording, t)!,
      subjectPalette: {
        for (final key in subjectPalette.keys)
          key: Color.lerp(subjectPalette[key], other.subjectPalette[key], t)!,
      },
      elevation: t < 0.5 ? elevation : other.elevation,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

/// The system UI font on each platform: SF Pro on macOS, Segoe on Windows.
const String? _uiFontFamily = null;

ThemeData buildTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark ? AppColors.dark : AppColors.light;

  TextStyle base(double size, FontWeight weight, Color color, {double? height, double? spacing}) =>
      TextStyle(
        fontFamily: _uiFontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.canvas,
    canvasColor: colors.canvas,
    dividerColor: colors.border,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
      surface: colors.surface,
    ),
    extensions: [colors],
    textTheme: TextTheme(
      displaySmall: base(34, FontWeight.w600, colors.textPrimary, height: 1.15, spacing: -0.6),
      headlineMedium: base(26, FontWeight.w600, colors.textPrimary, height: 1.2, spacing: -0.4),
      headlineSmall: base(20, FontWeight.w600, colors.textPrimary, height: 1.25, spacing: -0.2),
      titleMedium: base(15, FontWeight.w600, colors.textPrimary, height: 1.35),
      titleSmall: base(13, FontWeight.w600, colors.textSecondary, height: 1.35),
      bodyLarge: base(15, FontWeight.w400, colors.textPrimary, height: 1.5),
      bodyMedium: base(13.5, FontWeight.w400, colors.textSecondary, height: 1.5),
      bodySmall: base(12, FontWeight.w400, colors.textTertiary, height: 1.45),
      labelLarge: base(13, FontWeight.w500, colors.textPrimary),
      labelMedium: base(12, FontWeight.w500, colors.textSecondary),
      labelSmall: base(11, FontWeight.w500, colors.textTertiary, spacing: 0.4),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(8),
      thumbColor: WidgetStateProperty.all(colors.borderStrong),
      radius: const Radius.circular(4),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: base(11.5, FontWeight.w500, colors.canvas),
      waitDuration: const Duration(milliseconds: 500),
    ),
  );
}

/// Shared geometry so panels line up across pages.
class Insets {
  static const double page = 40;

  /// Desktop margins are too wide for a phone; every page reads this instead of
  /// hard-coding [page].
  static const double pageCompact = 20;

  static const double gutter = 24;
  static const double card = 18;

  static const double radius = 16;
  static const double radiusSmall = 10;
  static const double radiusLarge = 22;

  static const double maxContent = 860;

  /// Below this the shell switches from a sidebar to bottom navigation.
  static const double compactBreakpoint = 700;

  /// Height of the bottom navigation bar, excluding the safe area.
  static const double bottomNavHeight = 58;
}

/// One place to ask which layout the app is in.
extension LayoutContext on BuildContext {
  bool get isCompact => MediaQuery.sizeOf(this).width < Insets.compactBreakpoint;

  double get pageInset => isCompact ? Insets.pageCompact : Insets.page;
}
