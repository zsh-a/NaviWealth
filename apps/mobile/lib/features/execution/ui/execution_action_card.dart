part of 'execution_widgets.dart';

class ExecutionActionCard extends StatelessWidget {
  const ExecutionActionCard({
    super.key,
    required this.action,
    required this.onEdit,
    required this.onStart,
    required this.onBlock,
    required this.onResume,
    required this.onDone,
    required this.onDrop,
    required this.onRecordProgress,
    this.busy = false,
    this.projectLabel,
    this.commitmentLabel,
    this.onOpen,
  });

  final ExecutionAction action;
  final VoidCallback onEdit;
  final VoidCallback onStart;
  final VoidCallback onBlock;
  final VoidCallback onResume;
  final VoidCallback onDone;
  final VoidCallback onDrop;
  final VoidCallback onRecordProgress;
  final bool busy;
  final String? projectLabel;
  final String? commitmentLabel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusTone = _statusTone(action.status);
    final statusColor = _statusColor(context, action.status);
    final canStart = action.status == ExecutionActionStatus.todo;
    final canResume =
        action.status == ExecutionActionStatus.blocked ||
        action.status == ExecutionActionStatus.done ||
        action.status == ExecutionActionStatus.dropped;
    final canBlock =
        action.status == ExecutionActionStatus.todo ||
        action.status == ExecutionActionStatus.doing;
    final canDone = action.isOpen;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s14),
      level: SoftCardLevel.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CardOpenRegion(
                  onOpen: onOpen,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppIconTile(
                        icon: _statusIcon(action.status),
                        color: statusColor,
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
                            Text(
                              action.title,
                              style: context.rowTitleStyle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (action.note.trim().isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                action.note.trim(),
                                style: context.captionStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.s10),
                            Wrap(
                              spacing: AppSpacing.s6,
                              runSpacing: AppSpacing.s6,
                              children: [
                                AppBadge(
                                  label: executionStatusLabel(
                                    l10n,
                                    action.status,
                                  ),
                                  tone: statusTone,
                                  size: AppBadgeSize.compact,
                                ),
                                if (action.priority == ExecutionPriority.high)
                                  AppBadge(
                                    label: l10n.executionPriorityHigh,
                                    tone: AppBadgeTone.warning,
                                    size: AppBadgeSize.compact,
                                    icon: FLucideIcons.flag,
                                  ),
                                if (action.dueAt != null)
                                  AppBadge(
                                    label: l10n.executionDueBadge(
                                      executionDate(context, action.dueAt!),
                                    ),
                                    tone: AppBadgeTone.info,
                                    size: AppBadgeSize.compact,
                                    icon: FLucideIcons.calendarDays,
                                  ),
                                if (projectLabel != null)
                                  AppBadge(
                                    label:
                                        '${l10n.executionProjectField}: '
                                        '$projectLabel',
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
                                if (action.source.labelSnapshot != null &&
                                    action.source.labelSnapshot!.isNotEmpty)
                                  AppBadge(
                                    label: action.source.labelSnapshot!,
                                    size: AppBadgeSize.compact,
                                    icon: FLucideIcons.link,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              if (busy)
                const SizedBox(
                  width: AppIconSizes.xl,
                  height: AppIconSizes.xl,
                  child: Center(
                    child: FCircularProgress(
                      size: FCircularProgressSizeVariant.xs,
                    ),
                  ),
                )
              else
                _ActionQuickButtons(
                  canStart: canStart,
                  canResume: canResume,
                  canBlock: canBlock,
                  canDone: canDone,
                  onEdit: onEdit,
                  onStart: onStart,
                  onBlock: onBlock,
                  onResume: onResume,
                  onDone: onDone,
                  onDrop: onDrop,
                  onRecordProgress: onRecordProgress,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionQuickButtons extends StatelessWidget {
  const _ActionQuickButtons({
    required this.canStart,
    required this.canResume,
    required this.canBlock,
    required this.canDone,
    required this.onEdit,
    required this.onStart,
    required this.onBlock,
    required this.onResume,
    required this.onDone,
    required this.onDrop,
    required this.onRecordProgress,
  });

  final bool canStart;
  final bool canResume;
  final bool canBlock;
  final bool canDone;
  final VoidCallback onEdit;
  final VoidCallback onStart;
  final VoidCallback onBlock;
  final VoidCallback onResume;
  final VoidCallback onDone;
  final VoidCallback onDrop;
  final VoidCallback onRecordProgress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      alignment: WrapAlignment.end,
      children: [
        AppIconButton(
          icon: FLucideIcons.pencil,
          tooltip: l10n.executionEditActionTitle,
          onPress: onEdit,
          size: 32,
          iconSize: AppIconSizes.xs,
        ),
        AppIconButton(
          icon: FLucideIcons.messageSquareText,
          tooltip: l10n.executionCreateProgressTitle,
          onPress: onRecordProgress,
          size: 32,
          iconSize: AppIconSizes.xs,
        ),
        if (canStart)
          AppIconButton(
            icon: FLucideIcons.play,
            tooltip: l10n.executionActionStart,
            onPress: onStart,
            size: 32,
            iconSize: AppIconSizes.xs,
          ),
        if (canResume)
          AppIconButton(
            icon: FLucideIcons.rotateCcw,
            tooltip: l10n.executionActionResume,
            onPress: onResume,
            size: 32,
            iconSize: AppIconSizes.xs,
          )
        else if (canBlock)
          AppIconButton(
            icon: FLucideIcons.pause,
            tooltip: l10n.executionActionBlock,
            onPress: onBlock,
            size: 32,
            iconSize: AppIconSizes.xs,
          ),
        if (canDone)
          AppIconButton(
            icon: FLucideIcons.check,
            tooltip: l10n.executionActionDone,
            onPress: onDone,
            size: 32,
            iconSize: AppIconSizes.xs,
            iconColor: colors.primary,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
        if (canDone)
          AppIconButton(
            icon: FLucideIcons.archive,
            tooltip: l10n.executionActionDrop,
            onPress: onDrop,
            size: 32,
            iconSize: AppIconSizes.xs,
            iconColor: colors.mutedForeground,
          ),
      ],
    );
  }
}

IconData _statusIcon(ExecutionActionStatus status) {
  return switch (status) {
    ExecutionActionStatus.todo => FLucideIcons.circle,
    ExecutionActionStatus.doing => FLucideIcons.play,
    ExecutionActionStatus.blocked => FLucideIcons.octagonAlert,
    ExecutionActionStatus.done => FLucideIcons.checkCheck,
    ExecutionActionStatus.dropped => FLucideIcons.archive,
  };
}

AppBadgeTone _statusTone(ExecutionActionStatus status) {
  return switch (status) {
    ExecutionActionStatus.todo => AppBadgeTone.neutral,
    ExecutionActionStatus.doing => AppBadgeTone.info,
    ExecutionActionStatus.blocked => AppBadgeTone.error,
    ExecutionActionStatus.done => AppBadgeTone.success,
    ExecutionActionStatus.dropped => AppBadgeTone.neutral,
  };
}

Color _statusColor(BuildContext context, ExecutionActionStatus status) {
  final colors = context.theme.colors;
  final semantic = SemanticColors.of(context);
  return switch (status) {
    ExecutionActionStatus.todo => colors.mutedForeground,
    ExecutionActionStatus.doing => semantic.info,
    ExecutionActionStatus.blocked => semantic.danger,
    ExecutionActionStatus.done => semantic.success,
    ExecutionActionStatus.dropped => colors.mutedForeground,
  };
}
