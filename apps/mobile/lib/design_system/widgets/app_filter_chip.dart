import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/app_motion_policy.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/text_style_presets.dart';

/// Low-noise selectable filter chip for dense filter rows.
///
/// Use for filter facets and quick range choices. For mutually exclusive
/// high-level mode switches, prefer [SegmentedRow].
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.active,
    required this.onPress,
    this.onClear,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback? onPress;
  final VoidCallback? onClear;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final foreground = active ? colors.primary : colors.foreground;
    final background = active
        ? colors.primary.withValues(alpha: AppOpacity.light)
        : colors.muted.withValues(alpha: AppOpacity.disabled);
    final border = active
        ? colors.primary.withValues(alpha: AppOpacity.highlight)
        : colors.border.withValues(alpha: AppOpacity.highlight);

    return Semantics(
      button: true,
      selected: active,
      child: FTappable(
        onPress: onPress,
        child: AnimatedContainer(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          curve: Motion.standard,
          constraints: const BoxConstraints(minHeight: 34),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s10,
            vertical: AppSpacing.s6,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? (active ? FLucideIcons.check : FLucideIcons.circle),
                size: AppIconSizes.xs,
                color: active ? colors.primary : colors.mutedForeground,
              ),
              const SizedBox(width: AppSpacing.s6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (active
                              ? context.captionLabelStyle
                              : context.captionMediumStyle)
                          .copyWith(color: foreground),
                ),
              ),
              if (active && onClear != null) ...[
                const SizedBox(width: AppSpacing.s6),
                FTappable(
                  onPress: onClear,
                  child: Icon(
                    FLucideIcons.x,
                    size: AppIconSizes.xs,
                    color: colors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
