import 'package:flutter/material.dart';

/// Primitive color tokens from the branding guide. Widgets use [ColorScheme], not these.
abstract final class Palette {
  static const ink950 = Color(0xFF17202A);
  static const ink800 = Color(0xFF263746);
  static const ink600 = Color(0xFF526575);
  static const ink400 = Color(0xFF76828E); // 3.9:1 on paper050: control borders (WCAG 1.4.11)
  static const paper050 = Color(0xFFFCFBF7);
  static const paper100 = Color(0xFFF4F1EA);
  static const paper200 = Color(0xFFE8E3D8);
  static const copper700 = Color(0xFF8E4C2D); // text-size copper: 6.4:1 on paper050
  static const copper600 = Color(0xFFA65D3B);
  static const copper300 = Color(0xFFD69B7C); // dark-mode accent
  static const copper100 = Color(0xFFF2DED2);
  static const sage700 = Color(0xFF35705B);
  static const amber700 = Color(0xFF8A5B18);
  static const rose700 = Color(0xFF9B3F46);
  static const rose300 = Color(0xFFE0949B);
  static const blue700 = Color(0xFF285E86);
  static const night900 = Color(0xFF12181F);
  static const night800 = Color(0xFF1B232C);
  static const night700 = Color(0xFF26313C);
  static const night400 = Color(0xFF8795A3); // 5.3:1 on night900
}

ThemeData buildTheme() => _build(
      const ColorScheme.light(
        primary: Palette.copper700,
        onPrimary: Palette.paper050,
        primaryContainer: Palette.copper100,
        onPrimaryContainer: Palette.ink950,
        secondary: Palette.ink800,
        secondaryContainer: Palette.copper100,
        onSecondaryContainer: Palette.ink950,
        surface: Palette.paper050,
        onSurface: Palette.ink950,
        onSurfaceVariant: Palette.ink600,
        surfaceContainerHighest: Palette.paper100,
        outline: Palette.ink400,
        outlineVariant: Palette.paper200,
        error: Palette.rose700,
      ),
    );

ThemeData buildDarkTheme() => _build(
      const ColorScheme.dark(
        primary: Palette.copper300,
        onPrimary: Palette.night900,
        primaryContainer: Color(0xFF4A2D1E),
        onPrimaryContainer: Palette.paper100,
        secondary: Palette.paper200,
        secondaryContainer: Color(0xFF4A2D1E),
        onSecondaryContainer: Palette.paper100,
        surface: Palette.night900,
        onSurface: Palette.paper100,
        onSurfaceVariant: Color(0xFFB4BEC8),
        surfaceContainerHighest: Palette.night700,
        outline: Palette.night400,
        outlineVariant: Palette.night700,
        error: Palette.rose300,
      ),
    );

ThemeData _build(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    focusColor: scheme.brightness == Brightness.light ? Palette.blue700 : Palette.copper300,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
    ),
  );
}
