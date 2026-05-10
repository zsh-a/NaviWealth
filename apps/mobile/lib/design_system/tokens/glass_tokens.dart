import 'package:flutter/material.dart';

/// Surface hairline tokens (post-glass).
///
/// Originally backed a glassmorphism layer. After the Forui migration this
/// type is a flat helper that yields the hairline border colour and a
/// neutral surface fill matching the active brightness. Existing call
/// sites keep working; the visual is now flat rather than blurred.
@immutable
class GlassTokens {
  const GlassTokens({
    required this.surfaceColor,
    required this.hairlineColor,
    required this.borderRadius,
  });

  final Color surfaceColor;
  final Color hairlineColor;
  final double borderRadius;

  /// Glass blur retired — kept at 0 so any caller still feeding this into
  /// an `ImageFilter.blur` produces a no-op rather than a regression.
  double get blurSigma => 0;

  factory GlassTokens.dark() => const GlassTokens(
    surfaceColor: Color(0xFF18181B), // zinc-900
    hairlineColor: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
    borderRadius: 12,
  );

  factory GlassTokens.light() => const GlassTokens(
    surfaceColor: Color(0xFFFAFAFA), // zinc-50
    hairlineColor: Color(0x14000000), // rgba(0,0,0,0.08)
    borderRadius: 12,
  );

  /// Brightness-aware lookup. The class is no longer registered as a
  /// `ThemeExtension`; we resolve directly off `Theme.of(context)` so the
  /// caller does not need to install anything in `ThemeData.extensions`.
  static GlassTokens of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? GlassTokens.dark()
        : GlassTokens.light();
  }

  /// Glass support has been removed everywhere; callers that branch on
  /// this should fall through to the flat path.
  static bool isSupported() => false;

  GlassTokens copyWith({
    Color? surfaceColor,
    Color? hairlineColor,
    double? borderRadius,
  }) {
    return GlassTokens(
      surfaceColor: surfaceColor ?? this.surfaceColor,
      hairlineColor: hairlineColor ?? this.hairlineColor,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }
}
