import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import 'app_interaction.dart';

/// Canonical floating primary action shared by every LifeOS domain.
///
/// The compact circular surface uses the same restrained elevation and press
/// response as the rest of the design system. Domain pages supply semantics
/// and behavior without introducing their own glow, radius, or motion rules.
class AppFloatingActionSurface extends StatefulWidget {
  const AppFloatingActionSurface({
    super.key,
    required this.icon,
    required this.onPress,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPress;
  final String? tooltip;

  @override
  State<AppFloatingActionSurface> createState() =>
      _AppFloatingActionSurfaceState();
}

class _AppFloatingActionSurfaceState extends State<AppFloatingActionSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final background = _pressed
        ? Color.alphaBlend(
            colors.primaryForeground.withValues(alpha: AppOpacity.subtle),
            colors.primary,
          )
        : colors.primary;
    Widget button = Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            AppInteraction.signal(AppInteractionIntent.commit);
            widget.onPress();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1,
            duration: AppMotionPolicy.duration(context, Motion.tapFeedback),
            curve: Motion.standardDecelerate,
            child: AnimatedContainer(
              duration: AppMotionPolicy.duration(context, Motion.tapFeedback),
              curve: Motion.standardDecelerate,
              width: AppSpacing.s48,
              height: AppSpacing.s48,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                boxShadow: AppShadow.elevation2,
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.icon,
                size: AppIconSizes.lg,
                color: colors.primaryForeground,
              ),
            ),
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    if (tooltip != null && tooltip.isNotEmpty) {
      button = FTooltip(tipBuilder: (_, _) => Text(tooltip), child: button);
    }
    return button;
  }
}
