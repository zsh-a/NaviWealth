import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';

/// Shared inset-grouped surface used by settings, action menus and dense
/// business lists. One surface owns the visual grouping; rows inside it stay
/// flat and are separated by quiet, indented hairlines.
class AppGroupedSurface extends StatelessWidget {
  const AppGroupedSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final background = colors.brightness == Brightness.dark
        ? colors.card.withValues(alpha: AppOpacity.muted)
        : ColorPalette.surfaceRaised;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Standard divider for [AppGroupedSurface].
class AppGroupedDivider extends StatelessWidget {
  const AppGroupedDivider({
    super.key,
    this.indent = AppSpacing.s48,
    this.endIndent = 0,
  });

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      child: SizedBox(
        height: AppSpacing.hairline,
        child: ColoredBox(
          color: context.theme.colors.border.withValues(
            alpha: AppOpacity.faint,
          ),
        ),
      ),
    );
  }
}

class AppGroupedAction {
  const AppGroupedAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPress;
}

/// A compact, modern action surface for hub pages.
///
/// Use this when a page exposes several business destinations. It reads as
/// one grouped panel instead of a stack of unrelated cards.
class AppGroupedActionList extends StatelessWidget {
  const AppGroupedActionList({super.key, required this.actions});

  final List<AppGroupedAction> actions;

  @override
  Widget build(BuildContext context) {
    return AppGroupedSurface(
      child: Column(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            _ActionRow(action: actions[i]),
            if (i != actions.length - 1) const AppGroupedDivider(),
          ],
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final AppGroupedAction action;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      button: true,
      label: action.title,
      child: FTappable(
        onPress: action.onPress,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s2,
            vertical: action.subtitle.isEmpty ? AppSpacing.s14 : AppSpacing.s12,
          ),
          child: Row(
            children: [
              SizedBox(
                width: AppSpacing.s32,
                height: AppSpacing.s32,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Icon(
                    action.icon,
                    size: AppIconSizes.md,
                    color: colors.mutedForeground,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.labelStyle.copyWith(
                        color: colors.foreground,
                      ),
                    ),
                    if (action.subtitle.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        action.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.captionStyle,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Icon(
                FLucideIcons.chevronRight,
                size: AppIconSizes.sm,
                color: colors.mutedForeground.withValues(
                  alpha: AppOpacity.disabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
