import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_infinity/theme/app_theme.dart';
import 'package:self_infinity/theme/tokens.dart';

void main() {
  test('the design tokens are the values of docs/DESIGN.md Section 2', () {
    expect(AppColors.canvas, const Color(0xFFE6E6E1));
    expect(AppColors.background, const Color(0xFFF5F5F1));
    expect(AppColors.sidebar, const Color(0xFFEEEEE9));
    expect(AppColors.surface, const Color(0xFFFBFBF8));
    expect(AppColors.surfaceHigh, const Color(0xFFEBEBE6));
    expect(AppColors.userBubble, const Color(0xFFE2E2DC));
    expect(AppColors.outline, const Color(0xFFDEDED8));
    expect(AppColors.outlineStrong, const Color(0xFFC6C6BF));
    expect(AppColors.textPrimary, const Color(0xFF151514));
    expect(AppColors.textSecondary, const Color(0xFF565651));
    expect(AppColors.textTertiary, const Color(0xFF696963));
    expect(AppColors.primary, const Color(0xFF151514));
    expect(AppColors.primarySoft, const Color(0xFFECF2C9));
    expect(AppColors.glow, const Color(0xFFD4E57E));
    expect(AppColors.onAccent, const Color(0xFFFBFBF8));
    expect(AppColors.success, const Color(0xFF8A5B0C));
    expect(AppColors.successSoft, const Color(0xFFF5E6C3));
    expect(AppColors.danger, const Color(0xFFA23B2C));
    expect(AppColors.dangerSoft, const Color(0xFFF2DCD6));
    expect(AppColors.locked, const Color(0xFFC9C9C2));
    expect(AppColors.requires, const Color(0xFF8F8F88));
    expect(AppColors.link, AppColors.primary);
    expect([AppColors.ember, AppColors.emberHot, AppColors.emberRed], const [
      Color(0xFFF0B23E),
      Color(0xFFFFE0A0),
      Color(0xFFE0644E),
    ]);
    expect([AppColors.night, AppColors.nightHigh], const [Color(0xFF1A1A19), Color(0xFF2A2A28)]);
    expect(AppColors.magic, const [Color(0xFF3A2A10), Color(0xFFB7791F), Color(0xFFF0B23E)]);
    // Aliases.
    expect(AppColors.mastered, AppColors.success);
    expect(AppColors.xp, AppColors.success);
    expect(AppColors.loot, AppColors.success);
    expect(AppColors.warning, AppColors.danger);
    expect(
      [AppSpacing.xs, AppSpacing.sm, AppSpacing.md, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl],
      [4, 8, 12, 16, 24, 32],
    );
    expect([AppRadius.panel, AppRadius.card, AppRadius.chip, AppRadius.pill], [20, 16, 8, 28]);
    expect([AppRadius.bubble, AppRadius.bar, AppRadius.bubbleCorner], [20, 4, 4]);
    expect(AppLayout.sidePanelWidth, 280);
    expect(AppLayout.chatPanelWidth, 380);
    expect(AppLayout.panelGap, 12);
    expect(AppLayout.chatWidth, 720);
    expect(AppLayout.wideBreakpoint, 900);
  });

  test('the user bubble is round except the top right corner', () {
    final r = AppRadius.userBubbleBorder;
    expect(r.topLeft, const Radius.circular(20));
    expect(r.bottomLeft, const Radius.circular(20));
    expect(r.bottomRight, const Radius.circular(20));
    expect(r.topRight, const Radius.circular(4));
  });

  test('shadows are soft and wide: input, paper, float', () {
    final input = AppShadows.input.single;
    expect(input.blurRadius, 10);
    expect(input.color, const Color(0x0D000000));
    expect(AppShadows.paper.single.blurRadius, 18);
    final float = AppShadows.float.first;
    expect(float.offset, const Offset(0, 20));
    expect(float.blurRadius, 48);
    expect(float.color, const Color(0x1F000000));
  });

  test('the theme is a light Material 3 theme: paper canvas, ink actions', () {
    final theme = AppTheme.light();
    expect(theme.useMaterial3, isTrue);
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, AppColors.canvas);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.colorScheme.onPrimary, AppColors.onAccent);
    expect(theme.colorScheme.primaryContainer, AppColors.primarySoft);
    expect(theme.colorScheme.surface, AppColors.surface);
    expect(theme.colorScheme.error, AppColors.danger);
    expect(theme.cardTheme.color, AppColors.surface);
    expect(theme.dividerTheme.thickness, 1);
    expect(theme.dividerTheme.color, AppColors.outline);
    expect(theme.drawerTheme.backgroundColor, AppColors.canvas);
  });

  test('buttons are ink stadiums', () {
    final theme = AppTheme.light();
    final filled = theme.filledButtonTheme.style!;
    expect(filled.backgroundColor!.resolve({}), AppColors.primary);
    expect(filled.foregroundColor!.resolve({}), AppColors.onAccent);
    expect(filled.shape!.resolve({}), isA<StadiumBorder>());
    final outlined = theme.outlinedButtonTheme.style!;
    expect(outlined.shape!.resolve({}), isA<StadiumBorder>());
    expect(outlined.side!.resolve({})!.color, AppColors.outlineStrong);
    expect(theme.textButtonTheme.style!.shape!.resolve({}), isA<StadiumBorder>());
  });

  test('inputs are filled pills without a border; focus draws an ink edge', () {
    final input = AppTheme.light().inputDecorationTheme;
    expect(input.filled, isTrue);
    expect(input.fillColor, AppColors.surfaceHigh);
    final enabled = input.enabledBorder! as OutlineInputBorder;
    expect(enabled.borderSide, BorderSide.none);
    expect(enabled.borderRadius, AppRadius.pillBorder);
    final focused = input.focusedBorder! as OutlineInputBorder;
    expect(focused.borderSide.color, AppColors.primary);
  });

  test('type scale: sizes and restrained weights (DESIGN.md Section 2.2)', () {
    final t = AppTheme.light().textTheme;
    expect([t.headlineSmall!.fontSize, t.headlineSmall!.fontWeight], [20, FontWeight.w600]);
    expect([t.displaySmall!.fontSize, t.displaySmall!.fontWeight], [38, FontWeight.w400]);
    expect([t.displayMedium!.fontSize, t.displayMedium!.letterSpacing], [48, -0.6]);
    expect([t.headlineLarge!.fontSize, t.headlineLarge!.fontWeight], [36, FontWeight.w400]);
    // The display serif: headlines and big numbers only; it has one weight.
    for (final style in [t.displayLarge, t.displayMedium, t.displaySmall, t.headlineLarge]) {
      expect([style!.fontFamily, style.fontWeight], [AppFonts.display, FontWeight.w400]);
    }
    for (final style in [t.headlineMedium, t.titleLarge, t.bodyLarge, t.labelLarge]) {
      expect(style!.fontFamily, isNot(AppFonts.display));
    }
    expect(AppTheme.serif(t.titleLarge)?.fontFamily, AppFonts.display);
    expect([t.titleLarge!.fontSize, t.titleLarge!.fontWeight], [18, FontWeight.w600]);
    expect([t.titleMedium!.fontSize, t.titleMedium!.fontWeight], [15, FontWeight.w600]);
    expect(
      [t.bodyLarge!.fontSize, t.bodyLarge!.fontWeight, t.bodyLarge!.height],
      [16, FontWeight.w400, 1.6],
    );
    expect([t.bodyMedium!.fontSize, t.bodyMedium!.fontWeight], [15, FontWeight.w400]);
    expect([t.bodySmall!.fontSize, t.bodySmall!.color], [13, AppColors.textSecondary]);
    expect([t.labelLarge!.fontSize, t.labelLarge!.fontWeight], [14, FontWeight.w500]);
    expect([t.labelMedium!.fontSize, t.labelSmall!.fontSize], [13, 12]);
    expect(t.bodyMedium!.color, AppColors.textPrimary);
    for (final style in [
      t.displayLarge,
      t.headlineSmall,
      t.titleLarge,
      t.titleMedium,
      t.titleSmall,
      t.bodyLarge,
      t.bodyMedium,
      t.bodySmall,
      t.labelLarge,
      t.labelMedium,
      t.labelSmall,
    ]) {
      expect(style!.fontSize, isNotNull);
      expect(style.fontWeight!.value, lessThanOrEqualTo(600), reason: 'no weight above 600');
    }
  });

  test('Korean text falls back to the platform fonts; only the display serif is bundled', () {
    final family = AppTheme.light().textTheme.bodyMedium?.fontFamilyFallback;
    expect(family, containsAllInOrder(['Noto Sans KR', 'Apple SD Gothic Neo', 'Malgun Gothic']));
    expect(AppTheme.light().textTheme.bodyMedium?.fontFamily, isNot('Galmuri11'));
  });

  testWidgets('an AppBar title is 18 px (titleLarge) in the real widget tree', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(appBar: AppBar(title: const Text('Self-Infinity'))),
      ),
    );
    final text = tester.widget<Text>(find.text('Self-Infinity'));
    final style = DefaultTextStyle.of(tester.element(find.text('Self-Infinity'))).style
        .merge(text.style);
    expect(style.fontSize, 18);
  });

  test('page code has no colour, font or radius literals (DESIGN.md Section 5)', () {
    final banned = RegExp(
      r'Color\(0x|fontSize:|fontFamily:|BorderRadius\.circular\(\d|Colors\.(white|black|grey|red|blue|green)',
    );
    final offenders = <String>[];
    for (final dir in ['lib/features', 'lib/widgets', 'lib/app']) {
      for (final file in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (banned.hasMatch(lines[i])) offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
