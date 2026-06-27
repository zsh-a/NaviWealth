import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/execution_models.dart';

String executionDate(BuildContext context, DateTime date) {
  return AppFormatters(
    locale: Localizations.localeOf(context),
  ).date(date.toLocal());
}

String executionStatusLabel(
  AppLocalizations l10n,
  ExecutionActionStatus status,
) {
  return switch (status) {
    ExecutionActionStatus.todo => l10n.executionStatusTodo,
    ExecutionActionStatus.doing => l10n.executionStatusDoing,
    ExecutionActionStatus.blocked => l10n.executionStatusBlocked,
    ExecutionActionStatus.done => l10n.executionStatusDone,
    ExecutionActionStatus.dropped => l10n.executionStatusDropped,
  };
}

String executionProjectStatusLabel(
  AppLocalizations l10n,
  ExecutionProjectStatus status,
) {
  return switch (status) {
    ExecutionProjectStatus.active => l10n.executionProjectStatusActive,
    ExecutionProjectStatus.paused => l10n.executionProjectStatusPaused,
    ExecutionProjectStatus.completed => l10n.executionProjectStatusCompleted,
    ExecutionProjectStatus.archived => l10n.executionProjectStatusArchived,
  };
}

class ExecutionStateView extends StatelessWidget {
  const ExecutionStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: icon,
      title: title,
      message: message,
      action: action,
    );
  }
}

class ExecutionActionCard extends StatelessWidget {
  const ExecutionActionCard({
    super.key,
    required this.action,
    required this.onStart,
    required this.onBlock,
    required this.onResume,
    required this.onDone,
  });

  final ExecutionAction action;
  final VoidCallback onStart;
  final VoidCallback onBlock;
  final VoidCallback onResume;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusTone = _statusTone(action.status);
    final statusColor = _statusColor(context, action.status);
    final canStart = action.status == ExecutionActionStatus.todo;
    final canResume = action.status == ExecutionActionStatus.blocked;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s14),
      level: SoftCardLevel.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                          label: executionStatusLabel(l10n, action.status),
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
              const SizedBox(width: AppSpacing.s8),
              _ActionQuickButtons(
                canStart: canStart,
                canResume: canResume,
                onStart: onStart,
                onBlock: onBlock,
                onResume: onResume,
                onDone: onDone,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ExecutionSectionHeader extends StatelessWidget {
  const ExecutionSectionHeader({
    super.key,
    required this.title,
    required this.count,
    this.icon,
  });

  final String title;
  final int count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: AppIconSizes.xs, color: colors.mutedForeground),
          const SizedBox(width: AppSpacing.s6),
        ],
        Expanded(
          child: Text(
            title,
            style: context.captionLabelStyle.copyWith(
              color: colors.mutedForeground,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        AppBadge(
          label: count.toString(),
          size: AppBadgeSize.compact,
          minWidth: AppSpacing.s24,
        ),
      ],
    );
  }
}

class ExecutionCommitmentCard extends StatelessWidget {
  const ExecutionCommitmentCard({super.key, required this.commitment});

  final ExecutionCommitment commitment;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: FLucideIcons.target,
            color: colors.primary,
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
                  commitment.title,
                  style: context.rowTitleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (commitment.description.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    commitment.description.trim(),
                    style: context.bodyCaptionStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExecutionProjectCard extends StatelessWidget {
  const ExecutionProjectCard({super.key, required this.project});

  final ExecutionProject project;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s14),
      level: SoftCardLevel.raised,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconTile(
            icon: FLucideIcons.folder,
            color: colors.primary,
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
                  project.title,
                  style: context.rowTitleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (project.description.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    project.description.trim(),
                    style: context.bodyCaptionStyle,
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
                      label: executionProjectStatusLabel(l10n, project.status),
                      tone: project.status == ExecutionProjectStatus.paused
                          ? AppBadgeTone.warning
                          : AppBadgeTone.info,
                      size: AppBadgeSize.compact,
                    ),
                    if (project.targetDate != null)
                      AppBadge(
                        label: l10n.executionDueBadge(
                          executionDate(context, project.targetDate!),
                        ),
                        tone: AppBadgeTone.info,
                        size: AppBadgeSize.compact,
                        icon: FLucideIcons.calendarDays,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExecutionProgressCard extends StatelessWidget {
  const ExecutionProgressCard({super.key, required this.entry});

  final ExecutionProgressEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _progressColor(context, entry.kind);
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
                        _progressLabel(l10n, entry.kind),
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
              ],
            ),
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
    required this.onStart,
    required this.onBlock,
    required this.onResume,
    required this.onDone,
  });

  final bool canStart;
  final bool canResume;
  final VoidCallback onStart;
  final VoidCallback onBlock;
  final VoidCallback onResume;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      alignment: WrapAlignment.end,
      children: [
        if (canStart)
          AppIconButton(
            icon: FLucideIcons.play,
            tooltip: l10n.executionActionStart,
            onPress: onStart,
            size: 32,
            iconSize: AppIconSizes.xs,
          ),
        AppIconButton(
          icon: canResume ? FLucideIcons.rotateCcw : FLucideIcons.pause,
          tooltip: canResume
              ? l10n.executionActionResume
              : l10n.executionActionBlock,
          onPress: canResume ? onResume : onBlock,
          size: 32,
          iconSize: AppIconSizes.xs,
        ),
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

String _progressLabel(AppLocalizations l10n, ExecutionProgressKind kind) {
  return switch (kind) {
    ExecutionProgressKind.blocker => l10n.executionProgressKindBlocker,
    ExecutionProgressKind.completion => l10n.executionProgressKindCompletion,
    ExecutionProgressKind.dropped => l10n.executionProgressKindDropped,
    ExecutionProgressKind.scopeChange => l10n.executionProgressKindScope,
    ExecutionProgressKind.checkin => l10n.executionProgressKindCheckin,
  };
}
