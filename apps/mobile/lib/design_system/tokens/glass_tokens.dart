import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Build-time switch for the glassmorphism layer.
///
/// `BackdropFilter` with a non-trivial blur is a per-frame GPU cost that
/// craters frame rate on a few well-known fallbacks:
///
///  * Android < API 26 — the GPU pipeline doesn't pre-cache the blur and
///    every scroll frame re-runs the kernel; users on older hardware get
///    ~20 fps with the same surface stack that's silky on a modern Pixel.
///  * Safari ≤ 14 / iOS ≤ 14 — `backdrop-filter` is implemented but
///    composes in a way that breaks the rounded-rect mask on scrolls,
///    leaving artefact bands above the toolbar.
///
/// Rather than detect those at runtime (cost: a method-channel hop per
/// build), we expose a single compile-time switch. Consumer widgets read
/// [kEnableGlass] and pick between the blurred treatment and an opaque
/// fallback that uses the same [GlassTokens.surfaceColor] value layered
/// over `surface`.
///
/// Override at build time with `--dart-define=ENABLE_GLASS=false` (e.g. for
/// the legacy-Android channel build, or while bisecting a perf regression).
const bool kEnableGlass = bool.fromEnvironment(
  'ENABLE_GLASS',
  defaultValue: true,
);

/// Glassmorphism surface tokens — the blur sigma, surface tint, hairline
/// border, and rounded-rect radius used by every "glass" container in the
/// app (AppBar, BottomNav, sheets, AI floating pill).
///
/// Carried as a [ThemeExtension] so that:
///
///  1. The values swap when the theme flips light ↔ dark (dark uses a
///     stronger blur and a deeper surface tint — emulating "frosted onyx",
///     light uses a lighter blur over a near-white wash).
///  2. Tests and previews can override individual fields without
///     reconstructing a [ThemeData] from scratch.
///
/// The pieces:
///
///  * [blurSigma] — both x and y sigma fed into a [ImageFilter.blur].
///  * [surfaceColor] — the tint composited on top of the blurred backdrop;
///    its alpha defines how much of the layer underneath bleeds through.
///  * [hairlineColor] — the 1-px border drawn around glass containers so
///    they read as a discrete surface against an HDR backdrop.
///  * [borderRadius] — the corner radius that matches the rest of the
///    design system's "card" tier, kept here so consumers don't have to
///    cross-import [Radii] just to draw a glass card.
///
/// On platforms where [kEnableGlass] is false, callers should still read
/// [surfaceColor] but skip the [BackdropFilter] — the alpha is tuned so
/// that the surface still looks deliberate as a flat fill.
@immutable
class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.blurSigma,
    required this.surfaceColor,
    required this.hairlineColor,
    required this.borderRadius,
    this.specularColor = Colors.transparent,
    this.innerGlowColor = Colors.transparent,
  });

  final double blurSigma;
  final Color surfaceColor;
  final Color hairlineColor;
  final double borderRadius;

  /// Top-edge specular highlight for liquid glass depth simulation.
  final Color specularColor;

  /// Subtle inner edge glow that defines glass boundaries.
  final Color innerGlowColor;

  /// Dark-mode liquid glass — high blur (32) with very low alpha so content
  /// bleeds through. Specular highlight simulates light refraction on the
  /// top edge; inner glow defines the glass boundary.
  factory GlassTokens.dark() => const GlassTokens(
    blurSigma: 32,
    surfaceColor: Color(0x520D0E14), // rgba(13,14,20,0.32) — very translucent
    hairlineColor: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
    borderRadius: 24,
    specularColor: Color(0x18FFFFFF), // rgba(255,255,255,0.09)
    innerGlowColor: Color(0x0AFFFFFF), // rgba(255,255,255,0.04)
  );

  /// Light-mode liquid glass — medium blur (24) with moderate alpha for
  /// clean readability. Specular highlight adds a bright top edge;
  /// inner glow softly defines the glass boundary.
  factory GlassTokens.light() => const GlassTokens(
    blurSigma: 24,
    surfaceColor: Color(0x8AFFFFFF), // rgba(255,255,255,0.54) — translucent
    hairlineColor: Color(0x14000000), // rgba(0,0,0,0.08)
    borderRadius: 24,
    specularColor: Color(0x28FFFFFF), // rgba(255,255,255,0.16)
    innerGlowColor: Color(0x14000000), // rgba(0,0,0,0.08)
  );

  static GlassTokens of(BuildContext context) =>
      Theme.of(context).extension<GlassTokens>() ?? GlassTokens.light();

  /// Whether glass effects should be drawn for the current build target.
  ///
  /// Returns false on web (Safari/iOS-WebKit ≤14 fallback) and respects
  /// [kEnableGlass] for the build-time opt-out. Native iOS / Android
  /// (API 26+) is always considered supported — the build switch is the
  /// escape hatch for older Android.
  static bool isSupported() {
    if (!kEnableGlass) return false;
    if (kIsWeb) {
      // Conservative: prefer the opaque fallback on every web target.
      // Chromium and modern Safari handle backdrop-filter fine, but the
      // blur cost on long scroll lists is uneven enough that we'd rather
      // re-enable per-platform once T2 measures it.
      return false;
    }
    return true;
  }

  @override
  GlassTokens copyWith({
    double? blurSigma,
    Color? surfaceColor,
    Color? hairlineColor,
    double? borderRadius,
    Color? specularColor,
    Color? innerGlowColor,
  }) {
    return GlassTokens(
      blurSigma: blurSigma ?? this.blurSigma,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      hairlineColor: hairlineColor ?? this.hairlineColor,
      borderRadius: borderRadius ?? this.borderRadius,
      specularColor: specularColor ?? this.specularColor,
      innerGlowColor: innerGlowColor ?? this.innerGlowColor,
    );
  }

  @override
  GlassTokens lerp(ThemeExtension<GlassTokens>? other, double t) {
    if (other is! GlassTokens) return this;
    return GlassTokens(
      blurSigma: ui.lerpDouble(blurSigma, other.blurSigma, t)!,
      surfaceColor: Color.lerp(surfaceColor, other.surfaceColor, t)!,
      hairlineColor: Color.lerp(hairlineColor, other.hairlineColor, t)!,
      borderRadius: ui.lerpDouble(borderRadius, other.borderRadius, t)!,
      specularColor: Color.lerp(specularColor, other.specularColor, t)!,
      innerGlowColor: Color.lerp(innerGlowColor, other.innerGlowColor, t)!,
    );
  }
}
