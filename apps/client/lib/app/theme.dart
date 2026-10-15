import 'package:flutter/material.dart';

/// Primitive color tokens from the branding guide. Widgets use [ColorScheme], not these.
abstract final class Palette {
  static const ink950 = Color(0xFF17202A);
  static const ink800 = Color(0xFF263746);
  static const ink600 = Color(0xFF526575);
  static const paper050 = Color(0xFFFCFBF7);
  static const paper100 = Color(0xFFF4F1EA);
  static const paper200 = Color(0xFFE8E3D8);
  static const copper600 = Color(0xFFA65D3B);
  static const copper100 = Color(0xFFF2DED2);
  static const sage700 = Color(0xFF35705B);
  static const amber700 = Color(0xFF8A5B18);
  static const rose700 = Color(0xFF9B3F46);
  static const blue700 = Color(0xFF285E86);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: Palette.copper600,
    onPrimary: Palette.paper050,
    primaryContainer: Palette.copper100,
    onPrimaryContainer: Palette.ink950,
    secondary: Palette.ink800,
    surface: Palette.paper050,
    onSurface: Palette.ink950,
    surfaceContainerHighest: Palette.paper100,
    outline: Palette.paper200,
    error: Palette.rose700,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.paper050,
    focusColor: Palette.blue700,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
