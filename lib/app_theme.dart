import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'neumorphic.dart';

abstract final class AppTheme {
  static final light = _theme(Brightness.light);
  static final dark = _theme(Brightness.dark);

  static ThemeData neumorphic(NeuPalette palette) {
    final scheme = ColorScheme(
      brightness: palette.brightness,
      primary: palette.accent,
      onPrimary: palette.isDark ? const Color(0xFF241B0F) : Colors.white,
      primaryContainer: palette.lit,
      onPrimaryContainer: palette.onLit,
      secondary: palette.accent,
      onSecondary: palette.isDark ? const Color(0xFF241B0F) : Colors.white,
      secondaryContainer: palette.surfaceHigh,
      onSecondaryContainer: palette.text,
      tertiary: palette.tips,
      onTertiary: const Color(0xFF3A2A05),
      error: palette.isDark ? const Color(0xFFF08A7E) : const Color(0xFF9B3B2E),
      onError: palette.isDark ? const Color(0xFF301310) : Colors.white,
      errorContainer: palette.isDark
          ? const Color(0xFF4A2A26)
          : const Color(0xFFF7DDD8),
      onErrorContainer: palette.isDark
          ? const Color(0xFFFFDAD4)
          : const Color(0xFF5C1A12),
      surface: palette.base,
      onSurface: palette.text,
      onSurfaceVariant: palette.textDim,
      outline: palette.text.withValues(alpha: .28),
      outlineVariant: palette.separator,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: palette.base,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.surfaceHigh,
      surfaceContainerHighest: palette.well,
      inverseSurface: palette.lit,
      onInverseSurface: palette.onLit,
    );
    final radius = BorderRadius.circular(16);
    final base = ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.base,
      canvasColor: palette.base,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: palette.surfaceHigh,
      dividerTheme: DividerThemeData(
        color: palette.separator,
        space: 1,
        thickness: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.base,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: systemBars(palette.brightness),
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.surfaceHigh,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: TextStyle(color: palette.text, fontSize: 14),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.wellDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.outline),
        ),
        textStyle: TextStyle(color: palette.text, fontSize: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.well,
        hintStyle: TextStyle(color: palette.muted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.lit,
          foregroundColor: palette.onLit,
          disabledBackgroundColor: palette.well,
          disabledForegroundColor: palette.muted,
          elevation: 0,
          minimumSize: const Size(84, 46),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.text,
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          side: BorderSide(color: palette.outline),
          minimumSize: const Size(84, 46),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(palette.text),
          overlayColor: WidgetStatePropertyAll(palette.surfaceHigh),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: palette.well,
        side: BorderSide.none,
        labelStyle: TextStyle(color: palette.textDim, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: palette.accent, fontSize: 13),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceHigh,
        contentTextStyle: TextStyle(color: palette.text, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(999),
        thumbColor: WidgetStatePropertyAll(palette.text.withValues(alpha: .18)),
        crossAxisMargin: 2,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.wellDeep,
        circularTrackColor: palette.wellDeep,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        inactiveTrackColor: palette.wellDeep,
        thumbColor: palette.lit,
        overlayColor: palette.accent.withValues(alpha: .12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.onLit
              : palette.textDim,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.lit
              : palette.well,
        ),
        trackOutlineColor: WidgetStatePropertyAll(palette.outline),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.textDim,
        textColor: palette.text,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: palette.base,
        indicatorColor: palette.well,
        useIndicator: true,
        selectedIconTheme: IconThemeData(color: palette.accent, size: 24),
        unselectedIconTheme: IconThemeData(color: palette.muted, size: 24),
        selectedLabelTextStyle: TextStyle(
          color: palette.accent,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: TextStyle(color: palette.muted, fontSize: 12),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.accent,
        selectionColor: palette.accent.withValues(alpha: .25),
        selectionHandleColor: palette.accent,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: palette.text,
        displayColor: palette.text,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        bodyColor: palette.text,
        displayColor: palette.text,
      ),
    );
  }

  static ThemeMode mode(String preference) => switch (preference) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static String label(String preference) => switch (preference) {
    'light' => '浅色',
    'dark' => '深色',
    _ => '跟随系统',
  };

  static SystemUiOverlayStyle systemBars(Brightness brightness) {
    final icons = brightness == Brightness.dark
        ? Brightness.light
        : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      statusBarBrightness: brightness,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      systemNavigationBarContrastEnforced: false,
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? const Color(0xFF101114) : const Color(0xFFFAF8F6);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF664F),
      brightness: brightness,
      primary: dark ? const Color(0xFFFF765F) : const Color(0xFFAD3826),
      onPrimary: dark ? const Color(0xFF3B0E07) : Colors.white,
      primaryContainer: dark
          ? const Color(0xFF5C3027)
          : const Color(0xFFFFE0D8),
      onPrimaryContainer: dark
          ? const Color(0xFFFFE0D8)
          : const Color(0xFF4B160D),
      tertiary: dark ? const Color(0xFFF6C86B) : const Color(0xFF805500),
      surface: dark ? const Color(0xFF16171B) : Colors.white,
      onSurface: dark ? const Color(0xFFF2F0F4) : const Color(0xFF252328),
      onSurfaceVariant: dark
          ? const Color(0xFFB9B6C2)
          : const Color(0xFF68636C),
      outline: dark ? const Color(0xFF85818B) : const Color(0xFF7C757D),
      outlineVariant: dark ? const Color(0xFF34343D) : const Color(0xFFE3DFDC),
      surfaceContainerLowest: dark ? const Color(0xFF0D0E11) : Colors.white,
      surfaceContainerLow: dark
          ? const Color(0xFF191A20)
          : const Color(0xFFF7F3F0),
      surfaceContainer: dark
          ? const Color(0xFF1E2026)
          : const Color(0xFFF2EEEB),
      surfaceContainerHigh: dark
          ? const Color(0xFF25262D)
          : const Color(0xFFEDE8E5),
      surfaceContainerHighest: dark
          ? const Color(0xFF30313A)
          : const Color(0xFFE6E0DC),
      surfaceTint: Colors.transparent,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: systemBars(brightness),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: background,
        useIndicator: false,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
