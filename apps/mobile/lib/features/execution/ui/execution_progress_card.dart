part of 'execution_widgets.dart';

class ExecutionProgressCard extends StatelessWidget {
  const ExecutionProgressCard({
    super.key,
    required this.entry,
    this.actionLabel,
    this.projectLabel,
    this.commitmentLabel,
    this.onDelete,
  });

  final ExecutionProgressEntry entry;
  final String? actionLabel;
  final String? projectLabel;
  final String? commitmentLabel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _progressColor(context, entry.kind);
    final semantic = SemanticColors.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s14),
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
                        AppBadge(
                          label: '${l10n.executionActionField}: $actionLabel',
                          size: AppBadgeSize.compact,
                          icon: FLucideIcons.listTodo,
                        ),
                      if (projectLabel != null)
                        AppBadge(
                          label: '${l10n.executionProjectField}: $projectLabel',
                          size: AppBadgeSize.compact,
                          icon: FLucideIcons.folder,
                        ),
                      if (commitmentLabel != null)
                        AppBadge(
                          label:
                              '${l10n.executionCommitmentField}: '
                              '$commitmentLabel',
                          size: AppBadgeSize.compact,
                          icon: FLucideIcons.target,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: AppSpacing.s8),
            AppIconButton(
              icon: FLucideIcons.trash2,
              tooltip: l10n.commonDelete,
              onPress: onDelete,
              size: 32,
              iconSize: AppIconSizes.xs,
              iconColor: semantic.danger,
            ),
          ],
        ],
      ),
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
