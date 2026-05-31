import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design_system/design_system.dart';

/// Builds a [CustomTransitionPage] whose entrance animation depends on the
/// surface width:
///
/// * Mobile (`< Breakpoints.mobile`) — the familiar Material horizontal
///   slide from the right. Hero animations on the page run on top of it,
///   which matches the spec ("mobile: keep slide, mark hero").
/// * Tablet / Desktop (`>= Breakpoints.mobile`) — a 16dp horizontal
///   translate plus a fade over [Motion.slow] / [Motion.emphasizedDecelerate].
///   A full screen-width slide reads as visual noise on wide windows;
///   translate + fade keeps the transition calm and lets the Hero do the
///   visual work.
///
/// Use as the `pageBuilder` for a `GoRoute`:
///
/// ```dart
/// pageBuilder: (context, state) => buildHeroAwareTransitionPage(
///   context: context,
///   state: state,
///   child: AssetDetailPage(...),
/// ),
/// ```
CustomTransitionPage<T> buildHeroAwareTransitionPage<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: Motion.slow,
    reverseTransitionDuration: Motion.medium,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final width = MediaQuery.sizeOf(context).width;
      final isMobile = Breakpoints.isMobile(width);
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.emphasizedDecelerate,
        reverseCurve: Motion.standardAccelerate,
      );
      if (isMobile) {
        // Mobile: full-width slide from the right, like the Material
        // default — but driven through our motion tokens so duration /
        // curve match the rest of the app.
        final offset = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved);
        return SlideTransition(position: offset, child: child);
      }
      // Tablet / desktop: a fixed 16dp shift + fade. Heroes carry the
      // visual continuity; the page underneath just needs to feel
      // calmly settled in. We use `Transform.translate` rather than
      // `SlideTransition` so the offset stays a true 16dp regardless
      // of how wide the surface is.
      return FadeTransition(
        opacity: curved,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) => Transform.translate(
            offset: Offset(16 * (1 - curved.value), 0),
            child: child,
          ),
          child: child,
        ),
      );
    },
  );
}
