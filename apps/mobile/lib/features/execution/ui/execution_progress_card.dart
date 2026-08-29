part of 'execution_widgets.dart';

class ExecutionProgressCard extends StatelessWidget {
  const ExecutionProgressCard({
    super.key,
    required this.entry,
    this.actionLabel,
    this.planLabel,
    this.onEdit,
    this.onDelete,
    this.onActionOpen,
    this.onPlanOpen,
  });

  final ExecutionProgressEntry entry;
  final String? actionLabel;
  final String? planLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onActionOpen;
  final VoidCallback? onPlanOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _progressColor(context, entry.kind);
    final colors = context.theme.colors;
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: _progressIcon(entry.kind),
            color: color,
            size: 34,
            iconSize: AppIconSizes.sm,
            backgroundOpacity: AppOpacity.whisper,
            foregroundOpacity: 1,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        executionProgressKindLabel(l10n, entry.kind),
                        style: context.rowTitleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Text(
                      executionDate(context, entry.createdAt),
                      style: context.captionStyle,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  entry.note,
                  style: context.bodyCaptionStyle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (actionLabel != null || planLabel != null) ...[
                  const SizedBox(height: AppSpacing.s10),
                  Wrap(
                    spacing: AppSpacing.s6,
                    runSpacing: AppSpacing.s6,
                    children: actionLabel != null
                        ? [
                            _ProgressRelationBadge(
                              label:
                                  '${l10n.executionActionField}: $actionLabel',
                              icon: FLucideIcons.listTodo,
                              onPress: onActionOpen,
                            ),
                          ]
                        : [
                            if (executionRelationLabel(
                                  l10n: l10n,
                                  planLabel: planLabel,
                                )
                                case final relationLabel?)
                              _ProgressRelationBadge(
                                label: relationLabel,
                                icon: FLucideIcons.layers,
                                onPress: onPlanOpen,
                              ),
                          ],
                  ),
                ],
              ],
            ),
          ),
          if (onEdit != null || onDelete != null) ...[
            const SizedBox(width: AppSpacing.s8),
            AppAdaptiveActionMenu(
              title: executionProgressKindLabel(l10n, entry.kind),
              actions: [
                if (onEdit != null)
                  AppAdaptiveAction(
                    icon: FLucideIcons.pencil,
                    title: l10n.executionEditProgressTitle,
                    onPress: onEdit!,
                  ),
                if (onDelete != null)
                  AppAdaptiveAction(
                    icon: FLucideIcons.trash2,
                    title: l10n.commonDelete,
                    destructive: true,
                    onPress: onDelete!,
                  ),
              ],
              triggerBuilder: (context, openMenu, focusNode) => Focus(
                focusNode: focusNode,
                child: AppIconButton(
                  icon: FLucideIcons.ellipsis,
                  tooltip: l10n.shellMoreActions,
                  onPress: openMenu,
                  size: 32,
                  iconSize: AppIconSizes.xs,
                  iconColor: colors.mutedForeground,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressRelationBadge extends StatelessWidget {
  const _ProgressRelationBadge({
    required this.label,
    required this.icon,
    this.onPress,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final badge = AppBadge(
      label: label,
      size: AppBadgeSize.compact,
      icon: icon,
    );
    final onPress = this.onPress;
    if (onPress == null) return badge;
    return Semantics(
      button: true,
      label: label,
      child: AppTappable(onPress: onPress, child: badge),
    );
  }
}

IconData _progressIcon(ExecutionProgressKind kind) {
  return switch (kind) {
    ExecutionProgressKind.blocker => FLucideIcons.octagonAlert,
    ExecutionProgressKind.completion => FLucideIcons.checkCheck,
    ExecutionProgressKind.dropped => FLucideIcons.archive,
    ExecutionProgressKind.scopeChange => FLucideIcons.gitBranch,
    ExecutionProgressKind.checkin => FLucideIcons.messageSquareText,
  };
}

Color _progressColor(BuildContext context, ExecutionProgressKind kind) {
  final colors = context.theme.colors;
  final status = context.appTheme.status;
  return switch (kind) {
    ExecutionProgressKind.blocker => status.danger.fg,
    ExecutionProgressKind.completion => status.success.fg,
    ExecutionProgressKind.dropped => colors.mutedForeground,
    ExecutionProgressKind.scopeChange => status.warning.fg,
    ExecutionProgressKind.checkin => status.info.fg,
  };
}
