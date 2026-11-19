import 'package:flutter/material.dart';

// Original UI, original branding: neutral dark theme with a teal-green accent.
// Deliberately NOT styled like the commercial app's design language.
class MtTheme {
  static const bg = Color(0xFF101418);
  static const surface = Color(0xFF181E24);
  static const surfaceHi = Color(0xFF232B33);
  static const accent = Color(0xFF3DDC97);
  static const accentAlt = Color(0xFF6FB3FF);
  static const danger = Color(0xFFFF6B6B);
  static const text = Color(0xFFE8EDF2);
  static const textDim = Color(0xFF93A1AE);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: accentAlt,
        surface: surface,
        error: danger,
      ),
      scaffoldBackgroundColor: bg,
      fontFamily: 'Roboto',
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHi,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(color: textDim),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: const Color(0xFF0B1512),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: surfaceHi,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
      ),
    );
  }
}
