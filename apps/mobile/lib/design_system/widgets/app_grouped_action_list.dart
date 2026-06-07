import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import 'soft_card.dart';

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
    return SoftCard(
      borderless: true,
      borderRadius: AppRadius.xlg,
      level: SoftCardLevel.raised,
      child: Column(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            _ActionRow(action: actions[i]),
            if (i != actions.length - 1)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: AppSpacing.s64,
                ),
                child: SizedBox(
                  height: 1,
                  child: ColoredBox(
                    color: context.theme.colors.border.withValues(
                      alpha: AppOpacity.muted,
                    ),
                  ),
                ),
              ),
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
    return FTile(
      onPress: action.onPress,
      prefix: Container(
        width: AppSpacing.s40,
        height: AppSpacing.s40,
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: AppOpacity.subtle),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(action.icon, size: AppIconSizes.md, color: colors.primary),
      ),
      title: Text(
        action.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.theme.typography.sm.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        action.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.theme.typography.xs.copyWith(
          color: colors.mutedForeground,
        ),
      ),
      suffix: Icon(
        FLucideIcons.chevronRight,
        size: AppIconSizes.md,
        color: colors.mutedForeground.withValues(alpha: AppOpacity.scrim),
      ),
    );
  }
}
