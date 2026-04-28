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
}
