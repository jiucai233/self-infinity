/// The Material 3 light theme (`docs/DESIGN.md`): "Paper & Ember" — warm
/// grey paper, ink pill buttons, editorial type with tight display sizes.
library;

import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import 'tokens.dart';

/// Builds the app's [ThemeData]. Light only.
///
/// ```dart
/// MaterialApp(theme: AppTheme.light(language), ...)
/// ```
abstract final class AppTheme {
  static ColorScheme get colorScheme => const ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onAccent,
    primaryContainer: AppColors.primarySoft,
    onPrimaryContainer: AppColors.textPrimary,
    secondary: AppColors.textSecondary,
    onSecondary: AppColors.onAccent,
    secondaryContainer: AppColors.surfaceHigh,
    onSecondaryContainer: AppColors.textPrimary,
    tertiary: AppColors.success,
    onTertiary: AppColors.onAccent,
    tertiaryContainer: AppColors.successSoft,
    onTertiaryContainer: AppColors.success,
    error: AppColors.danger,
    onError: AppColors.onAccent,
    errorContainer: AppColors.dangerSoft,
    onErrorContainer: AppColors.danger,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    surfaceContainerLowest: AppColors.background,
    surfaceContainerLow: AppColors.canvas,
    surfaceContainer: AppColors.canvas,
    surfaceContainerHigh: AppColors.surfaceHigh,
    surfaceContainerHighest: AppColors.surfaceHigh,
    outline: AppColors.outlineStrong,
    outlineVariant: AppColors.outline,
    shadow: Color(0x14000000),
    scrim: Color(0x66000000),
    inverseSurface: AppColors.textPrimary,
    onInverseSurface: AppColors.background,
    inversePrimary: AppColors.background,
    surfaceTint: Colors.transparent,
  );

  /// A text theme with colors **and** sizes. (`ThemeData.textTheme` alone has
  /// no font sizes until `MaterialApp` localizes it, so styles copied from it
  /// into component themes — AppBar title, input hints, ... — would lack them.)
  ///
  /// Weights stay at 400 / 500 / 600; nothing is bold-black.
  static TextTheme _textTheme(ColorScheme scheme, AppLanguage language) {
    final typography = Typography.material2021(colorScheme: scheme);
    final base = typography.englishLike
        .merge(typography.black)
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
          fontFamily: AppFonts.sans,
          fontFamilyFallback: AppFonts.sansFallback(language),
        );
    TextStyle? t(TextStyle? s, double size, FontWeight w, [double height = 1.4, double tracking = 0]) =>
        s?.copyWith(fontSize: size, fontWeight: w, letterSpacing: tracking, height: height);
    // The display serif runs a little small for its size, hence the larger sizes; it has one
    // weight (400) and no Chinese or Korean, which come from the language's CJK serif.
    TextStyle? serif(TextStyle? s, double size, [double height = 1.1, double tracking = -0.3]) =>
        t(s, size, FontWeight.w400, height, tracking)?.copyWith(
          fontFamily: AppFonts.display,
          fontFamilyFallback: AppFonts.displayFallback(language),
        );
    return base.copyWith(
      // Display sizes are editorial headlines in the serif: big, tight, two lines at most.
      displayLarge: serif(base.displayLarge, 60, 1.02, -1.0),
      displayMedium: serif(base.displayMedium, 48, 1.05, -0.6),
      displaySmall: serif(base.displaySmall, 38, 1.1, -0.3),
      // Big numbers, also in the serif.
      headlineLarge: serif(base.headlineLarge, 36, 1.05, -0.2),
      headlineMedium: t(base.headlineMedium, 24, FontWeight.w600, 1.3),
      headlineSmall: t(base.headlineSmall, 20, FontWeight.w600, 1.3),
      titleLarge: t(base.titleLarge, 18, FontWeight.w600, 1.35),
      titleMedium: t(base.titleMedium, 15, FontWeight.w600),
      titleSmall: t(base.titleSmall, 14, FontWeight.w500),
      bodyLarge: t(base.bodyLarge, 16, FontWeight.w400, 1.6),
      bodyMedium: t(base.bodyMedium, 15, FontWeight.w400, 1.55),
      bodySmall: t(base.bodySmall, 13, FontWeight.w400, 1.45)?.copyWith(
        color: AppColors.textSecondary,
      ),
      labelLarge: t(base.labelLarge, 14, FontWeight.w500),
      labelMedium: t(base.labelMedium, 13, FontWeight.w500)?.copyWith(
        color: AppColors.textSecondary,
      ),
      labelSmall: t(base.labelSmall, 12, FontWeight.w500)?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }

  /// [style] in the display serif (weight 400, the only one it has), e.g.
  /// `AppTheme.serif(text.titleLarge)?.copyWith(fontStyle: FontStyle.italic)`
  /// for the identity quote. Pages may not name a font family themselves.
  static TextStyle? serif(TextStyle? style) => style?.copyWith(
    fontFamily: AppFonts.display,
    fontWeight: FontWeight.w400,
    fontFamilyFallback: AppFonts.displayFallback(LocaleController.current),
  );

  /// The light theme, with the fonts of [language] (English by default).
  static ThemeData light([AppLanguage language = AppLanguage.en]) =>
      _themes[language] ??= _light(language);

  static final Map<AppLanguage, ThemeData> _themes = {};

  static ThemeData _light(AppLanguage language) {
    final scheme = colorScheme;
    final text = _textTheme(scheme, language);
    final cardShape = RoundedRectangleBorder(
      borderRadius: AppRadius.cardBorder,
      side: const BorderSide(color: AppColors.outline),
    );
    const buttonShape = StadiumBorder();
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 10);
    const buttonMinSize = Size(64, 40);

    OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
      borderRadius: AppRadius.pillBorder,
      borderSide: color == Colors.transparent ? BorderSide.none : BorderSide(color: color),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.background,
      textTheme: text,
      primaryTextTheme: text,
      splashFactory: NoSplash.splashFactory,
      hoverColor: AppColors.surfaceHigh,
      highlightColor: AppColors.surfaceHigh,
      splashColor: Colors.transparent,
      dividerColor: AppColors.outline,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.outline, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        hintStyle: text.bodyMedium?.copyWith(color: AppColors.textTertiary),
        labelStyle: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall?.copyWith(color: AppColors.danger),
        border: inputBorder(Colors.transparent),
        enabledBorder: inputBorder(Colors.transparent),
        focusedBorder: inputBorder(AppColors.primary),
        errorBorder: inputBorder(AppColors.danger),
        focusedErrorBorder: inputBorder(AppColors.danger),
        disabledBorder: inputBorder(Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textTertiary,
          elevation: 0,
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textTertiary,
          elevation: 0,
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: const StadiumBorder(side: BorderSide(color: AppColors.outlineStrong)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          shape: buttonShape,
          side: const BorderSide(color: AppColors.outlineStrong),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: const Size(40, 36),
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          disabledForegroundColor: AppColors.textTertiary,
          shape: const CircleBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primarySoft,
        side: const BorderSide(color: AppColors.outlineStrong),
        labelStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chipBorder),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardBorder),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.outline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: const Color(0x1F000000),
        shape: cardShape,
        textStyle: text.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: text.bodyMedium?.copyWith(color: AppColors.onAccent),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chipBorder),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceHigh,
        circularTrackColor: AppColors.surfaceHigh,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.chipBorder),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: AppRadius.chipBorder,
        ),
        textStyle: text.bodySmall?.copyWith(color: AppColors.onAccent),
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 20),
    );
  }
}
