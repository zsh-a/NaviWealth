import 'package:flutter/widgets.dart';

import '../../core/haptics/haptics.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// Semantic interaction intents for a consistent emotional grammar (Phase F).
enum AppInteractionIntent {
  /// Primary button / FAB / confirm.
  commit,

  /// Chip, tab, filter, scrub tick.
  select,

  /// Soft reveal (expand section, open sheet content).
  reveal,

  /// Navigation push / domain switch.
  navigate,

  /// Destructive commit.
  destroy,

  /// Async success / save complete.
  success,

  /// Async failure.
  failure,
}

/// App-wide micro-interaction helpers.
///
/// Express *what happened*, not which haptic strength or duration.
class AppInteraction {
  const AppInteraction._();

  /// Fire haptic feedback for [intent].
  static void signal(AppInteractionIntent intent) {
    switch (intent) {
      case AppInteractionIntent.commit:
        Haptics.primaryPress();
      case AppInteractionIntent.select:
        Haptics.selection();
      case AppInteractionIntent.reveal:
        Haptics.selection();
      case AppInteractionIntent.navigate:
        Haptics.selection();
      case AppInteractionIntent.destroy:
        Haptics.destructive();
      case AppInteractionIntent.success:
        Haptics.success();
      case AppInteractionIntent.failure:
        Haptics.error();
    }
  }

  /// Wrap a callback with [intent] feedback.
  static VoidCallback? wrap(
    VoidCallback? callback, {
    AppInteractionIntent intent = AppInteractionIntent.commit,
  }) {
    if (callback == null) return null;
    return () {
      signal(intent);
      callback();
    };
  }
}

/// Focus mode: scale + dim the background when a sheet/dialog owns attention.
class FocusDim extends StatelessWidget {
  const FocusDim({
    super.key,
    required this.active,
    required this.child,
    this.scale = 0.985,
  });

  final bool active;
  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotionPolicy.duration(context, Motion.medium);
    return AnimatedScale(
      scale: active ? scale : 1,
      duration: duration,
      curve: Motion.emphasizedDecelerate,
      child: AnimatedOpacity(
        opacity: active ? AppOpacity.overlay : AppOpacity.opaque,
        duration: duration,
        curve: Motion.standard,
        child: child,
      ),
    );
  }
}

/// Soft fade+slide for page-level content swaps (domain switch, filter).
class ContentCrossFade extends StatelessWidget {
  const ContentCrossFade({
    super.key,
    required this.child,
    this.duration = Motion.medium,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotionPolicy.duration(context, duration),
      switchInCurve: Motion.emphasizedDecelerate,
      switchOutCurve: Motion.standardAccelerate,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: child,
    );
  }
}
