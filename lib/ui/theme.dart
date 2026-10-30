import 'package:flutter/material.dart';

/// Paper-and-ink palette. No gradients, no cards, no elevation.
class Palette {
  static const paper = Color(0xFFFAF9F6);
  static const paperDark = Color(0xFF17181A);
  static const ink = Color(0xFF1C1B19);
  static const inkDark = Color(0xFFE8E6E1);
  static const accent = Color(0xFFA8442B);
  static const accentDark = Color(0xFFE8B75A);
  static const muted = Color(0xFF8A8578);
  static const mutedDark = Color(0xFF8E8B84);
  static const rule = Color(0x14000000);
  static const ruleDark = Color(0x1AFFFFFF);

  static Color bg(bool dark) => dark ? paperDark : paper;
  static Color fg(bool dark) => dark ? inkDark : ink;
  static Color answer(bool dark) => dark ? accentDark : accent;
  static Color positive(bool dark) =>
      dark ? const Color(0xFF8FBF7E) : const Color(0xFF3F7A46);
  static Color negative(bool dark) =>
      dark ? const Color(0xFFE08A72) : const Color(0xFFAC3F2A);
  static Color faint(bool dark) => dark ? mutedDark : muted;
  static Color hairline(bool dark) => dark ? ruleDark : rule;
}

const monoFamily = 'monospace';

TextStyle editorStyle(bool dark, {double scale = 1}) => TextStyle(
  fontFamily: monoFamily,
  fontSize: 15 * scale,
  height: 28 / 15,
  color: Palette.fg(dark),
  letterSpacing: 0.1,
);

TextStyle answerStyle(bool dark, {double scale = 1}) => TextStyle(
  fontFamily: monoFamily,
  fontSize: 15 * scale,
  height: 28 / 15,
  color: Palette.answer(dark),
  fontFeatures: const [FontFeature.tabularFigures()],
);

ThemeData buildTheme(bool dark) {
  final fg = Palette.fg(dark);
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: Palette.bg(dark),
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.accent,
      brightness: dark ? Brightness.dark : Brightness.light,
      surface: Palette.bg(dark),
    ),
    textTheme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light)
        .textTheme
        .apply(bodyColor: fg, displayColor: fg),
    dividerColor: Palette.hairline(dark),
    splashFactory: InkSparkle.splashFactory,
    splashColor: Palette.accent.withValues(alpha: 0.10),
    highlightColor: Palette.accent.withValues(alpha: 0.06),
    hoverColor: Palette.accent.withValues(alpha: 0.05),
  );
}
