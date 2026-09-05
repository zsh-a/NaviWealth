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
    this.clearSemanticLabel,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback? onPress;
  final VoidCallback? onClear;
  final String? clearSemanticLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final foreground = active ? colors.primary : colors.foreground;
    final background = active
        ? colors.primary.withValues(alpha: AppOpacity.faint)
        : colors.background.withValues(alpha: AppOpacity.transparent);
    final border = active
        ? colors.primary.withValues(alpha: AppOpacity.highlight)
        : colors.border.withValues(alpha: AppOpacity.muted);

    final showClear = active && onClear != null;
    return AnimatedContainer(
      duration: AppMotionPolicy.duration(
        context,
        Motion.fast,
        role: AppMotionRole.decorative,
      ),
      curve: Motion.standard,
      constraints: const BoxConstraints(
        minHeight: AppControlHeights.touchTarget,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Semantics(
              button: onPress != null,
              selected: active,
              label: label,
              excludeSemantics: true,
              child: FTappable(
                onPress: onPress,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppControlHeights.touchTarget,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: AppSpacing.s10,
                      right: showClear ? AppSpacing.s4 : AppSpacing.s10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon ??
                              (active
                                  ? FLucideIcons.check
                                  : FLucideIcons.circle),
                          size: AppIconSizes.xs,
                          color: active
                              ? colors.primary
                              : colors.mutedForeground,
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showClear)
            Semantics(
              button: true,
              label: clearSemanticLabel ?? label,
              excludeSemantics: true,
              child: FTappable(
                onPress: onClear,
                child: SizedBox.square(
                  dimension: AppControlHeights.touchTarget,
                  child: Icon(
                    FLucideIcons.x,
                    size: AppIconSizes.xs,
                    color: colors.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
