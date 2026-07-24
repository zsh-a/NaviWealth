part of 'execution_widgets.dart';

class ExecutionProgressCard extends StatelessWidget {
  const ExecutionProgressCard({
    super.key,
    required this.entry,
    this.actionLabel,
    this.projectLabel,
    this.commitmentLabel,
    this.onEdit,
    this.onDelete,
    this.onActionOpen,
    this.onProjectOpen,
    this.onCommitmentOpen,
  });

  final ExecutionProgressEntry entry;
  final String? actionLabel;
  final String? projectLabel;
  final String? commitmentLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onActionOpen;
  final VoidCallback? onProjectOpen;
  final VoidCallback? onCommitmentOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _progressColor(context, entry.kind);
    final colors = context.theme.colors;
    return SoftCard.flat(
      borderless: true,
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
                if (actionLabel != null ||
                    projectLabel != null ||
                    commitmentLabel != null) ...[
                  const SizedBox(height: AppSpacing.s10),
                  Wrap(
                    spacing: AppSpacing.s6,
                    runSpacing: AppSpacing.s6,
                    children: [
                      if (actionLabel != null)
                        _ProgressRelationBadge(
                          label: '${l10n.executionActionField}: $actionLabel',
                          icon: FLucideIcons.listTodo,
                          onPress: onActionOpen,
                        ),
                      if (projectLabel != null)
                        _ProgressRelationBadge(
                          label: '${l10n.executionProjectField}: $projectLabel',
                          icon: FLucideIcons.folder,
                          onPress: onProjectOpen,
                        ),
                      if (commitmentLabel != null)
                        _ProgressRelationBadge(
                          label:
                              '${l10n.executionCommitmentField}: '
                              '$commitmentLabel',
                          icon: FLucideIcons.target,
                          onPress: onCommitmentOpen,
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
      child: FTappable(onPress: onPress, child: badge),
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
  final semantic = SemanticColors.of(context);
  return switch (kind) {
    ExecutionProgressKind.blocker => semantic.danger,
    ExecutionProgressKind.completion => semantic.success,
    ExecutionProgressKind.dropped => colors.mutedForeground,
    ExecutionProgressKind.scopeChange => semantic.warning,
    ExecutionProgressKind.checkin => semantic.info,
  };
}
