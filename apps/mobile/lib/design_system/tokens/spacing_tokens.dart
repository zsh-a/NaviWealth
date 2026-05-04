import 'package:flutter/widgets.dart';

/// 4-pt spacing scale.
///
/// Values map 1-to-1 to Figma spacing tokens (`spacing.s4` … `spacing.s64`).
/// Use these instead of magic numbers so layouts stay consistent across
/// platforms.
class Spacing {
  const Spacing._();

  static const double s0 = 0;
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s56 = 56;
  static const double s64 = 64;

  /// Default page-edge padding for mobile width.
  static const EdgeInsets pageMobile = EdgeInsets.all(s16);

  /// Default page-edge padding for tablet/desktop.
  static const EdgeInsets pageWide = EdgeInsets.all(s24);

  /// Padding inside a content card.
  static const EdgeInsets card = EdgeInsets.all(s16);

  /// Padding inside a hero card (e.g. net worth header).
  static const EdgeInsets cardHero = EdgeInsets.all(s20);

  /// Padding for section header labels (Apple News style).
  static const EdgeInsets sectionHeader = EdgeInsets.fromLTRB(s16, s20, s16, s8);

  /// Extra bottom clearance for scrollable content behind a floating
  /// glass bottom bar (Scaffold.extendBody = true).
  /// Combine with `MediaQuery.paddingOf(context).bottom` for the full inset.
  static const double floatingBarClearance = 64; // GlassBottomBar height

  /// Width of the AI Chat sessions side panel on desktop (FIR-93).
  /// Sized to fit a session title + timestamp + per-row action without
  /// truncating typical Chinese titles, while leaving the conversation
  /// pane the bulk of the width on a 1240+ dp window.
  static const double sessionsPanel = 320;

  /// Maximum content width for chat message rows on extra-wide windows
  /// (FIR-93). Caps line length on 4K monitors so messages stay readable
  /// instead of stretching the full pane width.
  static const double chatPaneMaxWidth = 960;
}
