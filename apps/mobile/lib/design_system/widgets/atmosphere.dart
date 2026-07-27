import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';

/// Time-of-day / mood wash for immersive canvas pages.
enum AtmospherePeriod { morning, day, evening, night }

/// Resolves a period from a clock hour (0–23).
AtmospherePeriod atmospherePeriodForHour(int hour) {
  if (hour < 5) return AtmospherePeriod.night;
  if (hour < 12) return AtmospherePeriod.morning;
  if (hour < 18) return AtmospherePeriod.day;
  return AtmospherePeriod.evening;
}

/// Soft radial + linear wash behind brief pages.
///
/// Keeps content readable: max ~6% brand / navy tint, never a decorative
/// illustration. Pair with [BriefScaffold] / [AppCanvasScaffold].
class AppAtmosphere extends StatelessWidget {
  const AppAtmosphere({
    super.key,
    required this.child,
    this.period,
    this.intensity = 1,
  });

  final Widget child;

  /// When null, uses the device clock.
  final AtmospherePeriod? period;

  /// 0–1 multiplier for wash strength.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final period = this.period ?? atmospherePeriodForHour(DateTime.now().hour);
    final wash = _wash(
      period: period,
      isDark: isDark,
      primary: colors.primary,
      cardSurface: context.appTheme.surfaces.card,
    );
    final top = wash.$1.withValues(alpha: wash.$1.a * intensity.clamp(0, 1));
    final mid = wash.$2.withValues(alpha: wash.$2.a * intensity.clamp(0, 1));

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomCenter,
                colors: [
                  top,
                  mid,
                  colors.background.withValues(alpha: AppOpacity.transparent),
                ],
                stops: const [0, 0.35, 0.72],
              ),
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -40,
          child: IgnorePointer(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    colors.primary.withValues(
                      alpha: isDark
                          ? AppOpacity.subtle * intensity
                          : AppOpacity.faint * intensity,
                    ),
                    colors.primary.withValues(alpha: AppOpacity.transparent),
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }

  (Color, Color) _wash({
    required AtmospherePeriod period,
    required bool isDark,
    required Color primary,
    required Color cardSurface,
  }) {
    if (isDark) {
      return switch (period) {
        AtmospherePeriod.morning => (
          ColorPalette.cyanBrand800.withValues(alpha: AppOpacity.medium),
          cardSurface.withValues(alpha: AppOpacity.subtle),
        ),
        AtmospherePeriod.day => (
          primary.withValues(alpha: AppOpacity.subtle),
          cardSurface.withValues(alpha: AppOpacity.whisper),
        ),
        AtmospherePeriod.evening => (
          ColorPalette.amber950.withValues(alpha: AppOpacity.disabled),
          primary.withValues(alpha: AppOpacity.faint),
        ),
        AtmospherePeriod.night => (
          ColorPalette.navy800.withValues(alpha: AppOpacity.highlight),
          cardSurface.withValues(alpha: AppOpacity.subtle),
        ),
      };
    }
    // Light wash is a cool canvas tint, not a second card layer — keep
    // readable contrast for white SoftCards while still feeling "premium".
    return switch (period) {
      AtmospherePeriod.morning => (
        ColorPalette.cyanBrand100.withValues(alpha: AppOpacity.disabled),
        ColorPalette.surfaceOverlay.withValues(alpha: AppOpacity.medium),
      ),
      AtmospherePeriod.day => (
        ColorPalette.cyanBrand50.withValues(alpha: AppOpacity.highlight),
        ColorPalette.surfaceOverlay.withValues(alpha: AppOpacity.light),
      ),
      AtmospherePeriod.evening => (
        ColorPalette.amber50.withValues(alpha: AppOpacity.strong),
        ColorPalette.surfaceOverlay.withValues(alpha: AppOpacity.medium),
      ),
      AtmospherePeriod.night => (
        ColorPalette.navy100.withValues(alpha: AppOpacity.medium),
        ColorPalette.surfaceOverlay.withValues(alpha: AppOpacity.light),
      ),
    };
  }
}
