import 'package:flutter/material.dart';

/// Design tokens shared by light/dark themes.
///
/// These are the only "magic numbers" in the design system — every widget
/// should reference values from here (or via [Theme.of]) rather than
/// hard-coding sizes, radii, or colors.
class DesignTokens {
  const DesignTokens._();

  // Brand seed — keep in sync with the marketing site & launcher icons.
  static const Color brandSeed = Color(0xFF1F6FEB);

  // Semantic accents (derive separately so we can map to ColorScheme.tertiary
  // and gain/loss indicators independently of the seed-based palette).
  static const Color gainGreen = Color(0xFF1B873F);
  static const Color lossRed = Color(0xFFD03640);
  static const Color warningAmber = Color(0xFFB45309);

  // Spacing scale (4-pt grid).
  static const double spaceXs = 4;
  static const double spaceS = 8;
  static const double spaceM = 12;
  static const double spaceL = 16;
  static const double spaceXl = 24;
  static const double spaceXxl = 32;

  // Corner radius scale.
  static const double radiusS = 8;
  static const double radiusM = 12;
  static const double radiusL = 16;
  static const double radiusXl = 24;

  // Elevation tokens (Material 3 surface tint variants are still used; these
  // are for explicit shadow elevations such as floating dialogs).
  static const double elevationFlat = 0;
  static const double elevationRaised = 1;
  static const double elevationFloating = 6;
}

/// Semantic colors (gain/loss/warning) attached to ThemeData via extension.
///
/// Read with `Theme.of(context).extension<SemanticColors>()!`.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.gain,
    required this.loss,
    required this.warning,
  });

  final Color gain;
  final Color loss;
  final Color warning;

  @override
  SemanticColors copyWith({Color? gain, Color? loss, Color? warning}) {
    return SemanticColors(
      gain: gain ?? this.gain,
      loss: loss ?? this.loss,
      warning: warning ?? this.warning,
    );
  }

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      gain: Color.lerp(gain, other.gain, t)!,
      loss: Color.lerp(loss, other.loss, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }

  static const SemanticColors light = SemanticColors(
    gain: DesignTokens.gainGreen,
    loss: DesignTokens.lossRed,
    warning: DesignTokens.warningAmber,
  );

  static const SemanticColors dark = SemanticColors(
    gain: Color(0xFF4ADE80),
    loss: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
  );
}
