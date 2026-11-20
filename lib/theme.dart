// Original UI, original branding: neutral palette with a teal-green accent.
// Deliberately NOT styled like the commercial app's design language.
//
// The palette is runtime-switchable (dark default, light since the light
// theme parity gap). Fields are non-const statics so every widget picks up
// the active palette on rebuild; screens must not mark expressions that use
// these as const (enforced by analysis).
// ignore: deprecated_member_use -- replacement package:material_ui is not published yet
import 'package:flutter/material.dart';

class _Palette {
  final Brightness brightness;
  final Color bg, surface, surfaceHi, accent, accentAlt, danger, text, textDim;
  const _Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.accent,
    required this.accentAlt,
    required this.danger,
    required this.text,
    required this.textDim,
  });
}

const _dark = _Palette(
  brightness: Brightness.dark,
  bg: Color(0xFF101418),
  surface: Color(0xFF181E24),
  surfaceHi: Color(0xFF232B33),
  accent: Color(0xFF3DDC97),
  accentAlt: Color(0xFF6FB3FF),
  danger: Color(0xFFFF6B6B),
  text: Color(0xFFE8EDF2),
  textDim: Color(0xFF93A1AE),
);

const _light = _Palette(
  brightness: Brightness.light,
  bg: Color(0xFFF4F6F8),
  surface: Color(0xFFFFFFFF),
  surfaceHi: Color(0xFFE8ECEF),
  accent: Color(0xFF1FA97A),
  accentAlt: Color(0xFF2E7CD6),
  danger: Color(0xFFD64545),
  text: Color(0xFF17202A),
  textDim: Color(0xFF5C6B78),
);

class MtTheme {
  static _Palette _p = _dark;

  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surfaceHi => _p.surfaceHi;
  static Color get accent => _p.accent;
  static Color get accentAlt => _p.accentAlt;
  static Color get danger => _p.danger;
  static Color get text => _p.text;
  static Color get textDim => _p.textDim;
  static Brightness get brightness => _p.brightness;

  /// Activates the palette for [brightness]. Returns true when the palette
  /// changed (the caller should repaint). Called from the MaterialApp
  /// builder (see main.dart) so all widgets pick it up on rebuild.
  static bool apply(Brightness brightness) {
    final next = brightness == Brightness.light ? _light : _dark;
    if (identical(next, _p)) return false;
    _p = next;
    return true;
  }

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: _p.brightness,
      colorScheme: (_p.brightness == Brightness.light
              ? ColorScheme.light
              : ColorScheme.dark)(
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
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHi,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        labelStyle: TextStyle(color: textDim),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: _p.brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF0B1512),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: surfaceHi,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
      ),
    );
  }
}
