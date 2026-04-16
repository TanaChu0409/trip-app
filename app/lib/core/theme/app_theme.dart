import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFFE8F0F8);
  static const backgroundSoft = Color(0xFFF6FAFF);
  static const surface = Color(0xFFF8FCFF);
  static const text = Color(0xFF0F2235);
  static const muted = Color(0xFF506882);
  static const accent = Color(0xFF003D79);
  static const accentStrong = Color(0xFF002B57);
  static const accentSoft = Color(0xFFC7DBF0);
}

class TripPaletteColor {
  const TripPaletteColor({
    required this.label,
    required this.hex,
    required this.color,
  });

  final String label;
  final String hex;
  final Color color;
}

class TripColors {
  static const defaultHex = '#003D79';

  static const presets = [
    TripPaletteColor(label: '海軍藍', hex: '#003D79', color: Color(0xFF003D79)),
    TripPaletteColor(label: '夕陽橘', hex: '#F97316', color: Color(0xFFF97316)),
    TripPaletteColor(label: '櫻桃紅', hex: '#E11D48', color: Color(0xFFE11D48)),
    TripPaletteColor(label: '森林綠', hex: '#15803D', color: Color(0xFF15803D)),
    TripPaletteColor(label: '湖水青', hex: '#0F766E', color: Color(0xFF0F766E)),
    TripPaletteColor(label: '葡萄紫', hex: '#7C3AED', color: Color(0xFF7C3AED)),
    TripPaletteColor(label: '莓果粉', hex: '#DB2777', color: Color(0xFFDB2777)),
    TripPaletteColor(label: '岩石棕', hex: '#92400E', color: Color(0xFF92400E)),
  ];
}

Color colorFromHex(String? hex, {Color fallback = AppColors.accent}) {
  if (hex == null || hex.isEmpty) {
    return fallback;
  }

  final normalized = hex.replaceAll('#', '').trim();
  if (normalized.length != 6 && normalized.length != 8) {
    return fallback;
  }

  final value = int.tryParse(normalized, radix: 16);
  if (value == null) {
    return fallback;
  }

  return Color(normalized.length == 6 ? value + 0xFF000000 : value);
}

String hexFromColor(Color color) {
  final rgbValue = color.toARGB32() & 0x00FFFFFF;
  return '#${rgbValue.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color tintColor(Color color, {double amount = 0.85}) {
  return Color.lerp(color, Colors.white, amount) ?? color;
}

Color shadeColor(Color color, {double amount = 0.25}) {
  return Color.lerp(color, Colors.black, amount) ?? color;
}

Color onAccentColor(Color color) {
  return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
      ? Colors.white
      : AppColors.text;
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.light,
    primary: AppColors.accent,
    surface: AppColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.text,
        height: 1.05,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: AppColors.muted,
        height: 1.55,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface.withValues(alpha: 0.92),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.08)),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.accent.withValues(alpha: 0.08),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(
        color: AppColors.accentStrong,
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.88),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: AppColors.accent.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
  );
}
