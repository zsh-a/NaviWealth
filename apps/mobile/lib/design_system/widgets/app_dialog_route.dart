import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/motion_tokens.dart';

/// App dialog route with a color scrim instead of a full-screen image filter.
///
/// Forui's default dialog barrier animates Gaussian blur on every frame. A
/// color barrier preserves the theme's dimming and dismissal semantics without
/// resampling the routed page beneath a moving overlay.
class AppDialogRoute<T> extends FDialogRoute<T> {
  AppDialogRoute({
    required super.style,
    required super.builder,
    required Duration duration,
    super.capturedFTheme,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.barrierDismissible,
    super.settings,
    super.useSafeArea = false,
  }) : _duration = duration;

  final Duration _duration;

  @override
  Duration get transitionDuration => _duration;

  @override
  Duration get reverseTransitionDuration => _duration;

  @override
  Widget buildModalBarrier() {
    final barrier = Builder(
      builder: (context) => AnimatedModalBarrier(
        color: animation!
            .drive(CurveTween(curve: barrierCurve))
            .drive(
              ColorTween(
                begin: Colors.transparent,
                end: offstage
                    ? Colors.transparent
                    : context.theme.colors.barrier,
              ),
            ),
        dismissible: barrierDismissible,
        semanticsLabel: barrierLabel,
        barrierSemanticsDismissible: semanticsDismissible,
        semanticsOnTapHint: barrierOnTapHint,
      ),
    );
    return capturedFTheme?.wrap(barrier) ?? barrier;
  }
}

/// Shared presentation seam for custom dialog bodies. The builder owns the
/// content transition; the route animates only the scrim.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required Widget Function(
    BuildContext context,
    FDialogStyle style,
    Animation<double> animation,
  )
  builder,
  bool barrierDismissible = true,
  RouteSettings? routeSettings,
}) {
  final navigator = Navigator.of(context);
  final localizations = FLocalizations.of(context) ?? FDefaultLocalizations();
  return navigator.push(
    AppDialogRoute<T>(
      style: context.theme.dialogRouteStyle,
      duration: AppMotionPolicy.duration(context, Motion.fast),
      capturedFTheme: FTheme.capture(from: context, to: navigator.context),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.barrierLabel,
      barrierOnTapHint: localizations.barrierOnTapHint(
        localizations.dialogSemanticsLabel,
      ),
      barrierDismissible: barrierDismissible,
      settings: routeSettings,
      builder: (context, animation) =>
          builder(context, context.theme.dialogStyle, animation),
    ),
  );
}
