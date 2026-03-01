import 'package:flutter/material.dart';

/// Colors extracted from the Kahili feather icon.
///
/// The icon is a neo-traditional flaming peacock feather with an all-seeing eye.
/// Dark charcoal body, fiery orange-red flames, golden sunburst,
/// electric cyan iris, emerald green lower body.
class KahiliColors {
  KahiliColors._();

  // ── Core palette ──────────────────────────────────────────────────────
  // Backgrounds — the feather's dark body
  static const Color bg = Color(0xFF0C0C14);
  static const Color surface = Color(0xFF151520);
  static const Color surfaceLight = Color(0xFF1C1C2E);
  static const Color surfaceBright = Color(0xFF242438);

  // Flame — primary accent (the fire crown)
  static const Color flame = Color(0xFFFF6D00);
  static const Color flameLight = Color(0xFFFF9100);
  static const Color flameDark = Color(0xFFE65100);

  // Cyan — secondary accent (the iris)
  static const Color cyan = Color(0xFF00E5FF);
  static const Color cyanMuted = Color(0xFF00ACC1);
  static const Color cyanDark = Color(0xFF006064);

  // Gold — tertiary (the sunburst rays)
  static const Color gold = Color(0xFFFFD600);
  static const Color goldMuted = Color(0xFFFFB300);

  // Emerald — success states (lower feather)
  static const Color emerald = Color(0xFF43A047);
  static const Color emeraldLight = Color(0xFF66BB6A);
  static const Color emeraldDark = Color(0xFF2E7D32);

  // Error — deep red from the flame tips
  static const Color error = Color(0xFFFF3D00);
  static const Color errorDark = Color(0xFFBF360C);

  // Text
  static const Color textPrimary = Color(0xFFE8E8F0);
  static const Color textSecondary = Color(0xFF9E9EB8);
  static const Color textTertiary = Color(0xFF5C5C78);

  // Borders & dividers
  static const Color border = Color(0xFF2A2A40);
  static const Color borderLight = Color(0xFF363650);

  // ── Semantic — issue severity (maps to Sentry levels) ─────────────
  static const Color fatal = Color(0xFFFF1744);
  static const Color errorLevel = Color(0xFFFF6D00); // same as flame
  static const Color warning = Color(0xFFFFD600);    // same as gold
  static const Color info = Color(0xFF00E5FF);        // same as cyan

  // ── Gradients ─────────────────────────────────────────────────────────
  static const LinearGradient flameGradient = LinearGradient(
    colors: [flameDark, flame, flameLight],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [cyanDark, cyanMuted, cyan],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [surface, surfaceLight],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static Color levelColor(String level) {
    switch (level) {
      case 'fatal':
        return fatal;
      case 'error':
        return errorLevel;
      case 'warning':
        return warning;
      case 'info':
        return info;
      default:
        return textSecondary;
    }
  }
}

class KahiliTheme {
  KahiliTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      scaffoldBackgroundColor: KahiliColors.bg,

      colorScheme: const ColorScheme.dark(
        primary: KahiliColors.flame,
        onPrimary: Colors.black,
        primaryContainer: KahiliColors.flameDark,
        onPrimaryContainer: KahiliColors.flameLight,
        secondary: KahiliColors.cyan,
        onSecondary: Colors.black,
        secondaryContainer: KahiliColors.cyanDark,
        onSecondaryContainer: KahiliColors.cyan,
        tertiary: KahiliColors.gold,
        onTertiary: Colors.black,
        error: KahiliColors.error,
        surface: KahiliColors.surface,
        onSurface: KahiliColors.textPrimary,
        onSurfaceVariant: KahiliColors.textSecondary,
        outline: KahiliColors.border,
        outlineVariant: KahiliColors.borderLight,
      ),

      // ── App bar ───────────────────────────────────────────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: KahiliColors.surface,
        foregroundColor: KahiliColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: KahiliColors.flame,
      ),

      // ── Navigation bar (bottom tabs) ──────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: KahiliColors.surface,
        indicatorColor: KahiliColors.flame.withAlpha(40),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: KahiliColors.flame);
          }
          return const IconThemeData(color: KahiliColors.textTertiary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: KahiliColors.flame,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: KahiliColors.textTertiary,
            fontSize: 12,
          );
        }),
        surfaceTintColor: Colors.transparent,
      ),

      // ── Cards ─────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: KahiliColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: KahiliColors.border, width: 1),
        ),
      ),

      // ── List tiles ────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        tileColor: Colors.transparent,
      ),

      // ── Divider ───────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: KahiliColors.border,
        thickness: 1,
        space: 1,
      ),

      // ── Buttons ───────────────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: KahiliColors.flame,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),

      // ── Snack bar ─────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: KahiliColors.surfaceBright,
        contentTextStyle: const TextStyle(color: KahiliColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Text ──────────────────────────────────────────────────────────
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: KahiliColors.textPrimary, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: KahiliColors.textPrimary, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: KahiliColors.textSecondary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: KahiliColors.textPrimary),
        bodyMedium: TextStyle(color: KahiliColors.textPrimary),
        bodySmall: TextStyle(color: KahiliColors.textSecondary),
        labelLarge: TextStyle(color: KahiliColors.textPrimary, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: KahiliColors.textSecondary),
        labelSmall: TextStyle(color: KahiliColors.textTertiary),
      ),

      // ── Progress indicator ────────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: KahiliColors.flame,
      ),
    );
  }
}
