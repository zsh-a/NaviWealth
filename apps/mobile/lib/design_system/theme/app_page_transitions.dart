import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Details enter with a 16dp directional reveal; the outgoing page is static.
/// Peer navigation is animated separately by the retained shell content.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration =>
      AppMotionPolicy.platformDuration(Motion.pageTransition);

  @override
  Duration get reverseTransitionDuration =>
      AppMotionPolicy.platformDuration(Motion.pageReturn);

  /// Shared detail transition: a bounded 16dp reveal, or an accessible fade.
  ///
  /// Exposed statically so imperative routes ([buildAppPageRoute]) default to
  /// the exact same motion as theme-driven declarative routes.
  static Widget buildAppTransition(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    final reduced = AppMotionPolicy.reduceMotion(context);
    final disabled = AppMotionPolicy.disableAnimations(context);
    final width = MediaQuery.sizeOf(context).width;
    final curved = animation.drive(
      CurveTween(curve: Motion.standardDecelerate),
    );
    final progress = disabled ? kAlwaysCompleteAnimation : curved;
    final fraction = !reduced && width > 0 ? AppSpacing.s16 / width : 0.0;
    return FadeTransition(
      opacity: progress,
      child: SlideTransition(
        textDirection: Directionality.of(context),
        position: Tween<Offset>(
          begin: Offset(fraction, 0),
          end: Offset.zero,
        ).animate(progress),
        child: child,
      ),
    );
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Keep the outgoing page static while a new route enters. Moving and
    // dimming a large page (especially an AI conversation with Markdown,
    // tool cards, and charts) forces its entire render tree to participate in
    // the transition. The incoming page already supplies the visual cue;
    // leaving the old page static also makes every AI-originated deep link
    // cheaper without requiring route-specific knowledge here.
    return buildAppTransition(context, animation, child);
  }
}

/// Native iOS navigation, including edge-swipe back, with accessible fallbacks.
class AppCupertinoPageTransitionsBuilder
    extends CupertinoPageTransitionsBuilder {
  const AppCupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration =>
      AppMotionPolicy.platformDuration(super.transitionDuration);

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      AppMotionPolicy.platformReduceMotion ? null : super.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = AppMotionPolicy.reduceMotion(context);
    final disabled = AppMotionPolicy.disableAnimations(context);
    // Keep Cupertino's gesture detector mounted even when spatial motion is
    // reduced. Its live route controller still commits/cancels the back drag.
    return super.buildTransitions(
      route,
      context,
      reduced ? kAlwaysCompleteAnimation : animation,
      reduced ? kAlwaysDismissedAnimation : secondaryAnimation,
      FadeTransition(
        opacity: reduced && !disabled ? animation : kAlwaysCompleteAnimation,
        child: child,
      ),
    );
  }
}
