import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/dimens_tokens.dart';
import 'app_actions.dart';
import 'app_interaction.dart';

/// A tonal filter option or removable applied condition.
/// Menu triggers disclose their picker; ordinary selected options show a check.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.active,
    required this.onPress,
    this.onClear,
    this.clearSemanticLabel,
    this.icon,
  }) : _trigger = false;

  const AppFilterChip.trigger({
    super.key,
    required this.label,
    required this.active,
    required this.onPress,
    this.onClear,
    this.clearSemanticLabel,
    this.icon,
  }) : _trigger = true;

  final String label;
  final bool active;
  final VoidCallback? onPress;
  final VoidCallback? onClear;
  final String? clearSemanticLabel;
  final IconData? icon;
  final bool _trigger;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final radius = BorderRadius.circular(
      theme.visual.continuousCorners ? AppRadius.lg : AppRadius.md,
    );
    final showClear = active && onClear != null;
    final enabled = onPress != null || showClear;
    final leading =
        icon ?? (active && !showClear && !_trigger ? FLucideIcons.check : null);
    final background = Color.alphaBlend(
      (active ? theme.accent.fg : theme.content.strong).withValues(
        alpha: active ? AppOpacity.softTint : AppOpacity.faint,
      ),
      theme.surfaces.card,
    );
    final content = Padding(
      padding: EdgeInsetsDirectional.only(
        start: AppSpacing.s12,
        end: showClear ? AppSpacing.s4 : AppSpacing.s12,
        top: AppSpacing.s8,
        bottom: AppSpacing.s8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            Icon(
              leading,
              size: AppIconSizes.xs,
              color: active ? theme.accent.fg : theme.content.muted,
            ),
            const SizedBox(width: AppSpacing.s6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  (active
                          ? theme.type.numericCaptionStrong
                          : theme.type.numericCaption)
                      .copyWith(
                        color: enabled
                            ? theme.content.strong
                            : theme.content.muted,
                      ),
            ),
          ),
          if (_trigger) ...[
            const SizedBox(width: AppSpacing.s6),
            Icon(
              FLucideIcons.chevronDown,
              size: AppIconSizes.xs,
              color: theme.content.muted,
            ),
          ],
        ],
      ),
    );
    return DecoratedBox(
      decoration: theme.visual.decoration(
        radius: radius,
        color: background,
        side: MediaQuery.highContrastOf(context)
            ? BorderSide(
                color: active ? theme.accent.fg : theme.surfaces.border,
              )
            : BorderSide.none,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: _action(
              context,
              label: label,
              onPress: onPress,
              selected: active,
              radius: radius,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppControlHeights.touchTarget,
                ),
                child: content,
              ),
            ),
          ),
          if (showClear)
            _action(
              context,
              label: clearSemanticLabel ?? label,
              onPress: onClear,
              radius: radius,
              child: SizedBox.square(
                dimension: AppControlHeights.touchTarget,
                child: Icon(
                  FLucideIcons.x,
                  size: AppIconSizes.xs,
                  color: theme.content.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _action(
    BuildContext context, {
    required String label,
    required VoidCallback? onPress,
    required BorderRadius radius,
    required Widget child,
    bool selected = false,
  }) {
    if (onPress == null) {
      return Semantics(
        label: label,
        selected: selected,
        button: false,
        child: ExcludeSemantics(child: child),
      );
    }
    return AppActionTappable(
      semanticsLabel: label,
      selected: selected,
      onPress: AppInteraction.wrap(
        onPress,
        intent: AppInteractionIntent.select,
      ),
      focusedOutlineStyle: FFocusedOutlineStyleDelta.delta(
        borderRadius: radius,
      ),
      builder: (context, variants, child) => DecoratedBox(
        decoration: context.appTheme.visual.decoration(
          radius: radius,
          color: context.appTheme.content.strong.withValues(
            alpha: variants.contains(FTappableVariant.pressed)
                ? AppOpacity.light
                : variants.contains(FTappableVariant.hovered)
                ? AppOpacity.faint
                : AppOpacity.transparent,
          ),
        ),
        child: child,
      ),
      child: child,
    );
  }
}
