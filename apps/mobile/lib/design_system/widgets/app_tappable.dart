import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'app_interaction.dart';

/// The app's default tappable row/tile primitive.
///
/// Raw `FTappable` ships with *no* hover visual and an opt-in focus ring, so
/// every bare call site was invisible to keyboard traversal and mouse hover
/// (desktop-citizenship audit §7). This wrapper makes the desktop states
/// non-optional:
///
/// * keyboard focus → the theme focus ring, rounded to [borderRadius];
/// * hover / press → a shared, motion-aware state tint;
/// * Enter/Space activation comes with `FTappable` itself.
///
/// Every press also fires [AppInteractionIntent.select] feedback so standard
/// taps share one uniform micro-interaction; call sites must not signal it
/// again manually.
///
/// Use it for every tappable row, tile and cell outside the design system.
/// (`SoftCard` has its own richer treatment; buttons go through the
/// `app_actions` family.)
class AppTappable extends StatelessWidget {
  const AppTappable({
    super.key,
    required this.child,
    this.onPress,
    this.onLongPress,
    this.semanticsLabel,
    this.selected = false,
    this.excludeSemantics = false,
    this.behavior,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.md)),
  });

  final Widget child;
  final VoidCallback? onPress;
  final VoidCallback? onLongPress;
  final String? semanticsLabel;
  final bool selected;
  final bool excludeSemantics;
  final HitTestBehavior? behavior;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Shape of the focus ring — match the row's own corner treatment.
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return FTappable(
      onPress: AppInteraction.wrap(
        onPress,
        intent: AppInteractionIntent.select,
      ),
      onLongPress: onLongPress,
      semanticsLabel: semanticsLabel,
      selected: selected,
      excludeSemantics: excludeSemantics,
      behavior: behavior ?? HitTestBehavior.translucent,
      autofocus: autofocus,
      focusNode: focusNode,
      focusedOutlineStyle: FFocusedOutlineStyleDelta.delta(
        borderRadius: borderRadius,
      ),
      builder: (context, variants, child) {
        final enabled = !variants.contains(FTappableVariant.disabled);
        final colors = context.theme.colors;
        final alpha = !enabled
            ? 0.0
            : variants.contains(FTappableVariant.pressed)
            ? AppOpacity.light
            : variants.contains(FTappableVariant.hovered)
            ? AppOpacity.faint
            : 0.0;
        return AnimatedContainer(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          curve: Motion.standardDecelerate,
          decoration: BoxDecoration(
            color: (selected ? colors.primary : colors.foreground).withValues(
              alpha: alpha,
            ),
            borderRadius: borderRadius,
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}
