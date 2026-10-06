/// Design tokens (`docs/DESIGN.md`): "Paper & Ember", Material 3 light.
library;

import 'package:flutter/material.dart';

/// Font families. Everything is the platform sans (Roboto on the web) except
/// the display serif, which the theme puts on the display styles and
/// `headlineLarge` (big numbers); [AppTheme.serif] puts it on anything else
/// (the identity quote). It has one weight, 400: never make it bold.
abstract final class AppFonts {
  /// Instrument Serif (OFL), bundled in `assets/fonts/`.
  static const String display = 'InstrumentSerif';
}

/// Colors. "Paper & Ember": warm grey paper, near-black ink for every action,
/// gold only where something was earned, and a dark "night" panel for the
/// life tree. Few colors; the light comes from the tree itself.
abstract final class AppColors {
  /// The app canvas behind the panels.
  static const Color canvas = Color(0xFFE6E6E1);

  /// The stage panel.
  static const Color background = Color(0xFFF5F5F1);

  /// Side panels (left panel, chat panel): a shade darker than the stage.
  static const Color sidebar = Color(0xFFEEEEE9);

  /// Cards: paper lifted off the panel.
  static const Color surface = Color(0xFFFBFBF8);

  /// Filled controls: the input bar, her bubble, hover.
  static const Color surfaceHigh = Color(0xFFEBEBE6);

  /// The user's chat bubble.
  static const Color userBubble = Color(0xFFE2E2DC);

  /// Hairline borders and dividers.
  static const Color outline = Color(0xFFDEDED8);

  /// Stronger borders (chips, secondary buttons).
  static const Color outlineStrong = Color(0xFFC6C6BF);

  static const Color textPrimary = Color(0xFF151514);
  static const Color textSecondary = Color(0xFF565651);
  // 4.5:1 or better on background, surface and surfaceHigh (WCAG AA for small text).
  static const Color textTertiary = Color(0xFF696963);

  /// Ink: the send button, filled buttons, links, ready nodes.
  static const Color primary = Color(0xFF151514);

  /// Pale lime: selected rows, highlights, unlocked chips.
  static const Color primarySoft = Color(0xFFECF2C9);

  /// Lime edge light on the selected / focused thing.
  static const Color glow = Color(0xFFD4E57E);

  /// Text/icon color on top of [primary], [danger], [night].
  static const Color onAccent = Color(0xFFFBFBF8);

  /// Earned: passed audits, cleared nodes, XP (amber ink, readable on paper).
  static const Color success = Color(0xFF8A5B0C);
  static const Color successSoft = Color(0xFFF5E6C3);

  /// Same as [success]; kept for older call sites.
  static const Color mastered = success;

  /// Rewards (XP) and lesson cards.
  static const Color xp = success;
  static const Color loot = success;

  /// Failed audits, errors.
  static const Color danger = Color(0xFFA23B2C);
  static const Color dangerSoft = Color(0xFFF2DCD6);

  /// `contradicts`, low condition. Same red as [danger].
  static const Color warning = danger;

  /// Locked nodes.
  static const Color locked = Color(0xFFC9C9C2);

  /// Edges of the skill tree.
  static const Color requires = Color(0xFF8F8F88);

  /// Links.
  static const Color link = primary;

  /// Fire: cleared nodes and sparks on the night panel.
  static const Color ember = Color(0xFFF0B23E);
  static const Color emberHot = Color(0xFFFFE0A0);

  /// Failed nodes on the night panel.
  static const Color emberRed = Color(0xFFE0644E);

  /// The night panel of the life tree and the inside of the crystal ball.
  static const Color night = Color(0xFF1A1A19);
  static const Color nightHigh = Color(0xFF2A2A28);

  /// Wires and text on [night].
  static const Color nightLine = Color(0xFF8E8E87);
  static const Color nightText = Color(0xFFEEEEE9);
  static const Color nightMuted = Color(0xFF6F6F69);

  /// The crystal ball's smoky glass: lit centre, body, shaded edge (`OrbAvatar`).
  static const List<Color> glass = [Color(0xFF45453F), Color(0xFF242422), Color(0xFF0E0E0D)];

  /// Light on glass (highlights, the sweep).
  static const Color shine = Color(0xFFFFFFFF);

  /// Bronze to gold: the "magic" moments (thinking shimmer, voice, celebration).
  static const List<Color> magic = [Color(0xFF3A2A10), Color(0xFFB7791F), Color(0xFFF0B23E)];
}

/// Spacing scale: 4 / 8 / 12 / 16 / 24 / 32.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii.
abstract final class AppRadius {
  /// Cards and dialogs.
  static const double card = 16;

  /// The big panels of the layout (NotebookLM).
  static const double panel = 20;

  /// Buttons, chips, small controls.
  static const double chip = 8;

  /// The chat input bar and round icon buttons (ChatGPT-style pill).
  static const double pill = 28;

  /// Chat bubbles (Gemini).
  static const double bubble = 20;

  /// The stat bars of the left panel (height 8, fully rounded).
  static const double bar = 4;

  /// The sharp corner of the user's chat bubble (top right).
  static const double bubbleCorner = 4;

  /// The user's chat bubble: round, except the top-right corner (Gemini).
  static BorderRadius get userBubbleBorder => const BorderRadius.only(
    topLeft: Radius.circular(bubble),
    bottomLeft: Radius.circular(bubble),
    bottomRight: Radius.circular(bubble),
    topRight: Radius.circular(bubbleCorner),
  );

  static BorderRadius get cardBorder => BorderRadius.circular(card);
  static BorderRadius get panelBorder => BorderRadius.circular(panel);
  static BorderRadius get chipBorder => BorderRadius.circular(chip);
  static BorderRadius get pillBorder => BorderRadius.circular(pill);
}

/// Shadows: soft and wide, like paper on a desk.
abstract final class AppShadows {
  static const List<BoxShadow> input = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 2)),
  ];

  /// Cards lifted off a panel (stat cards, the node sheet's back sheets).
  static const List<BoxShadow> paper = [
    BoxShadow(color: Color(0x12000000), blurRadius: 18, offset: Offset(0, 6)),
  ];

  /// Floating cards (the node sheet, the celebration card, menus).
  static const List<BoxShadow> float = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 48, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2)),
  ];
}

/// Layout rules.
abstract final class AppLayout {
  /// Content is centered and at most this wide on wide screens.
  static const double maxContentWidth = 1100;

  /// The chat column and input bar are at most this wide (ChatGPT-like).
  static const double chatWidth = 720;

  /// Width of the left panel.
  static const double sidePanelWidth = 280;

  /// Width of the chat panel (conversation is the point, so it is wider).
  static const double chatPanelWidth = 380;

  /// Gap between the panels and around them (NotebookLM).
  static const double panelGap = 12;

  /// Side gutter on phones.
  static const double gutter = 16;

  /// From this width on, the side panels are shown; below it they are drawers.
  static const double wideBreakpoint = 900;

  /// The landing hero switches to its desktop layout here (brand, tags and
  /// labels shown, footer in a row).
  static const double heroBreakpoint = 768;

  /// Whether the current window counts as wide (≥ [wideBreakpoint]).
  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wideBreakpoint;
}
