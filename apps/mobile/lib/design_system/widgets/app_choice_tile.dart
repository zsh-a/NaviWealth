import 'package:flutter/widgets.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'app_tappable.dart';

/// A single-choice row or tile with the shared opaque tonal selection surface.
///
/// Keep the visible selection cue (a check or active badge) in [child]. The
/// surface owns geometry, contrast boundaries, semantics and tap feedback.
class AppChoiceTile extends StatelessWidget {
  const AppChoiceTile({
    super.key,
    required this.selected,
    required this.onPress,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.s12),
  });

  final bool selected;
  final VoidCallback? onPress;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final radius = BorderRadius.circular(
      theme.visual.continuousCorners ? AppRadius.lg : AppRadius.md,
    );
    final fill = selected
        ? Color.alphaBlend(
            theme.accent.fg.withValues(alpha: AppOpacity.softTint),
            theme.surfaces.card,
          )
        : theme.surfaces.card;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: AnimatedContainer(
        duration: AppMotionPolicy.duration(
          context,
          Motion.fast,
          role: AppMotionRole.decorative,
        ),
        curve: Motion.standardDecelerate,
        decoration: theme.visual.decoration(
          radius: radius,
          color: fill,
          side: MediaQuery.highContrastOf(context)
              ? BorderSide(
                  color: selected ? theme.accent.fg : theme.surfaces.border,
                )
              : BorderSide.none,
        ),
        child: AppTappable(
          selected: selected,
          onPress: onPress,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppControlHeights.touchTarget,
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
