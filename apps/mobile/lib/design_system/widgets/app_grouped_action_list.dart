import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../tokens/color_palette.dart';
import '../tokens/dimens_tokens.dart';

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
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final background = isDark
        ? colors.card.withValues(alpha: AppOpacity.muted)
        : ColorPalette.neutral75;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xlg),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s10),
        child: Column(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              _ActionRow(action: actions[i]),
              if (i != actions.length - 1)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.s48,
                  ),
                  child: SizedBox(
                    height: AppSpacing.hairline,
                    child: ColoredBox(
                      color: colors.border.withValues(alpha: AppOpacity.faint),
                    ),
                  ),
                ),
            ],
          ],
        ),
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
                      style: context.theme.typography.sm.copyWith(
                        color: colors.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (action.subtitle.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        action.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.theme.typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
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
