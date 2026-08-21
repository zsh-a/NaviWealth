import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';

/// A compact, layout-stable marker for selected navigation and mode controls.
///
/// The marker keeps selection visible without placing another filled card
/// inside an existing navigation or control surface. Its slot never changes
/// size, so switching destinations does not move labels or icons.
class AppSelectionIndicator extends StatelessWidget {
  const AppSelectionIndicator({
    super.key,
    required this.selected,
    this.axis = Axis.horizontal,
    this.length = AppSpacing.s20,
    this.thickness = AppStroke.accent,
    this.color,
  });

  final bool selected;
  final Axis axis;
  final double length;
  final double thickness;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotionPolicy.duration(
      context,
      Motion.fast,
      role: AppMotionRole.decorative,
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: axis == Axis.horizontal ? length : thickness,
        height: axis == Axis.horizontal ? thickness : length,
        child: AnimatedOpacity(
          duration: duration,
          curve: Motion.standard,
          opacity: selected ? 1 : 0,
          child: AnimatedScale(
            duration: duration,
            curve: Motion.standardDecelerate,
            scale: selected ? 1 : 0.55,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color ?? context.theme.colors.primary,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
