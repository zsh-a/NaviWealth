import 'package:flutter/material.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/breakpoints.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Width-aware route transition applied to every Material-backed route via
/// [ThemeData.pageTransitionsTheme].
///
/// * Mobile (`< Breakpoints.mobile`) — the familiar horizontal slide from
///   the right, driven through the app motion curves so duration/easing match
///   the rest of the app. Hero animations run on top of it.
/// * Tablet / Desktop (`>= Breakpoints.mobile`) — a 16dp horizontal
///   translate plus a fade. A full screen-width slide reads as visual noise
///   on wide windows; translate + fade keeps the transition calm and lets
///   the Hero do the visual work.
/// * Reduce motion — a plain cross-fade.
///
/// Registering this at the theme level means plain `GoRoute(builder:)`
/// declarations get the correct transition on every surface; routes never
/// need a bespoke `pageBuilder` for chrome.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  /// The shared transition visual: width-aware slide (mobile) or a 16dp
  /// translate + fade (wide viewports), plain cross-fade under reduce-motion.
  ///
  /// Exposed statically so imperative routes ([buildAppPageRoute]) default to
  /// the exact same motion as theme-driven declarative routes.
  static Widget buildAppTransition(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    if (AppMotionPolicy.reduceMotion(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final width = MediaQuery.sizeOf(context).width;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Motion.emphasizedDecelerate,
      reverseCurve: Motion.standardAccelerate,
    );
    if (Breakpoints.isMobile(width)) {
      final offset = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved);
      return SlideTransition(position: offset, child: child);
    }
    // SlideTransition with a fractional offset (16px / screen-width) lets the
    // render object handle the shift directly without per-frame Transforms.
    final fraction = width > 0 ? AppSpacing.s16 / width : 0.0;
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(fraction, 0),
          end: Offset.zero,
        ).animate(curved),
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
    final incoming = buildAppTransition(context, animation, child);
    if (AppMotionPolicy.reduceMotion(context)) {
      // buildAppTransition already resolved to a plain cross-fade.
      return incoming;
    }
    // Outgoing-page parallax (iOS-style): while the next route pushes in,
    // this page drifts a fraction of its width in the exit direction and
    // dims slightly instead of freezing underneath the incoming page.
    final curved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Motion.emphasizedDecelerate,
      reverseCurve: Motion.standardAccelerate,
    );
    final width = MediaQuery.sizeOf(context).width;
    // Mobile exits by ~30% of the page width; wide viewports keep the same
    // calm 16dp translate as the entrance so the shift stays subtle.
    final exitFraction = Breakpoints.isMobile(width)
        ? 0.3
        : (width > 0 ? AppSpacing.s16 / width : 0.0);
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.75).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: Offset(-exitFraction, 0),
        ).animate(curved),
        child: incoming,
      ),
    );
  }
}
