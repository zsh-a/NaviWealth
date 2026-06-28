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

String executionCommitmentStatusLabel(
  AppLocalizations l10n,
  ExecutionCommitmentStatus status,
) {
  return switch (status) {
    ExecutionCommitmentStatus.active => l10n.executionProjectStatusActive,
    ExecutionCommitmentStatus.paused => l10n.executionProjectStatusPaused,
    ExecutionCommitmentStatus.completed => l10n.executionProjectStatusCompleted,
    ExecutionCommitmentStatus.archived => l10n.executionProjectStatusArchived,
  };
}

String executionPriorityLabel(
  AppLocalizations l10n,
  ExecutionPriority priority,
) {
  return switch (priority) {
    ExecutionPriority.low => l10n.executionPriorityLow,
    ExecutionPriority.normal => l10n.executionPriorityNormal,
    ExecutionPriority.high => l10n.executionPriorityHigh,
  };
}

String executionHorizonLabel(AppLocalizations l10n, ExecutionHorizon horizon) {
  return switch (horizon) {
    ExecutionHorizon.week => l10n.executionHorizonWeek,
    ExecutionHorizon.month => l10n.executionHorizonMonth,
    ExecutionHorizon.quarter => l10n.executionHorizonQuarter,
    ExecutionHorizon.open => l10n.executionHorizonOpen,
  };
}

String executionProgressKindLabel(
  AppLocalizations l10n,
  ExecutionProgressKind kind,
) {
  return switch (kind) {
    ExecutionProgressKind.blocker => l10n.executionProgressKindBlocker,
    ExecutionProgressKind.completion => l10n.executionProgressKindCompletion,
    ExecutionProgressKind.dropped => l10n.executionProgressKindDropped,
    ExecutionProgressKind.scopeChange => l10n.executionProgressKindScope,
    ExecutionProgressKind.checkin => l10n.executionProgressKindCheckin,
  };
}

enum ExecutionTodayFilter { focus, backlog, blocked, high, due }

String executionTodayFilterLabel(
  AppLocalizations l10n,
  ExecutionTodayFilter filter,
) {
  return switch (filter) {
    ExecutionTodayFilter.focus => l10n.executionOverviewFocus,
    ExecutionTodayFilter.backlog => l10n.executionOverviewBacklog,
    ExecutionTodayFilter.blocked => l10n.executionOverviewBlocked,
    ExecutionTodayFilter.high => l10n.executionOverviewHigh,
    ExecutionTodayFilter.due => l10n.executionOverviewDue,
  };
}

IconData executionTodayFilterIcon(ExecutionTodayFilter filter) {
  return switch (filter) {
    ExecutionTodayFilter.focus => FLucideIcons.sun,
    ExecutionTodayFilter.backlog => FLucideIcons.inbox,
    ExecutionTodayFilter.blocked => FLucideIcons.octagonAlert,
    ExecutionTodayFilter.high => FLucideIcons.flag,
    ExecutionTodayFilter.due => FLucideIcons.calendarClock,
  };
}

List<ExecutionAction> filteredExecutionActions({
  required ExecutionTodayFilter filter,
  required List<ExecutionAction> todayActions,
  required List<ExecutionAction> openActions,
  required DateTime now,
}) {
  final open = openActions.where((action) => action.isOpen);
  return switch (filter) {
    ExecutionTodayFilter.focus => todayActions,
    ExecutionTodayFilter.backlog =>
      open.where((action) => action.isBacklog).toList(growable: false),
    ExecutionTodayFilter.blocked =>
      open
          .where((action) => action.status == ExecutionActionStatus.blocked)
          .toList(growable: false),
    ExecutionTodayFilter.high =>
      open
          .where((action) => action.priority == ExecutionPriority.high)
          .toList(growable: false),
    ExecutionTodayFilter.due =>
      open.where((action) => action.isDue(now)).toList(growable: false),
  };
}

String? executionProjectRelationLabel(
  List<ExecutionProject> projects,
  String? projectId,
) {
  if (projectId == null || projectId.isEmpty) return null;
  for (final project in projects) {
    if (project.id == projectId) return project.title;
  }
  return projectId;
}

String? executionCommitmentRelationLabel(
  List<ExecutionCommitment> commitments,
  String? commitmentId,
) {
  if (commitmentId == null || commitmentId.isEmpty) return null;
  for (final commitment in commitments) {
    if (commitment.id == commitmentId) return commitment.title;
  }
  return commitmentId;
}

class ExecutionOverviewStrip extends StatelessWidget {
  const ExecutionOverviewStrip({
    super.key,
    required this.snapshot,
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  final ExecutionOverviewSnapshot snapshot;
  final ExecutionTodayFilter selectedFilter;
  final ValueChanged<ExecutionTodayFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
    final tiles = <_OverviewTileData>[
      _OverviewTileData(
        label: l10n.executionOverviewFocus,
        value: snapshot.todayCount,
        icon: FLucideIcons.sun,
        color: semantic.info,
        filter: ExecutionTodayFilter.focus,
      ),
      _OverviewTileData(
        label: l10n.executionOverviewBlocked,
        value: snapshot.blockedCount,
        icon: FLucideIcons.octagonAlert,
        color: semantic.danger,
        filter: ExecutionTodayFilter.blocked,
      ),
      _OverviewTileData(
        label: l10n.executionOverviewBacklog,
        value: snapshot.backlogCount,
        icon: FLucideIcons.inbox,
        color: colors.primary,
        filter: ExecutionTodayFilter.backlog,
      ),
      _OverviewTileData(
        label: l10n.executionOverviewHigh,
        value: snapshot.highPriorityCount,
        icon: FLucideIcons.flag,
        color: semantic.warning,
        filter: ExecutionTodayFilter.high,
      ),
      _OverviewTileData(
        label: l10n.executionOverviewDue,
        value: snapshot.dueCount,
        icon: FLucideIcons.calendarClock,
        color: colors.primary,
        filter: ExecutionTodayFilter.due,
      ),
      _OverviewTileData(
        label: l10n.executionOverviewProjects,
        value: snapshot.activeProjectCount,
        icon: FLucideIcons.folder,
        color: colors.primary,
      ),
      _OverviewTileData(
        label: l10n.executionOverviewCommitments,
        value: snapshot.activeCommitmentCount,
        icon: FLucideIcons.target,
        color: colors.primary,
      ),
      _OverviewTileData(
        label: l10n.executionOverviewProgress7d,
        value: snapshot.recentProgressCount,
        icon: FLucideIcons.clipboardCheck,
        color: semantic.success,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.s8;
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 760
            ? 4
            : maxWidth >= 360
            ? 2
            : 1;
        final tileWidth = maxWidth.isFinite
            ? (maxWidth - gap * (columns - 1)) / columns
            : AppControlWidths.metricTile;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: tileWidth,
                child: _ExecutionOverviewTile(
                  data: tile,
                  selected:
                      tile.filter != null && tile.filter == selectedFilter,
                  onPress: tile.filter == null
                      ? null
                      : () => onFilterChanged(tile.filter!),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OverviewTileData {
  const _OverviewTileData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.filter,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final ExecutionTodayFilter? filter;
}

class _ExecutionOverviewTile extends StatelessWidget {
  const _ExecutionOverviewTile({
    required this.data,
    required this.selected,
    required this.onPress,
  });

  final _OverviewTileData data;
  final bool selected;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final color = selected ? colors.primary : data.color;
    return Semantics(
      selected: selected,
      child: SoftCard(
        padding: const EdgeInsets.all(AppSpacing.s12),
        level: selected ? SoftCardLevel.raised : SoftCardLevel.flat,
        onPress: onPress,
        child: Row(
          children: [
            AppIconTile(
              icon: data.icon,
              color: color,
              size: 32,
              iconSize: AppIconSizes.xs,
              radius: AppRadius.sm,
            ),
            const SizedBox(width: AppSpacing.s10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.value.toString(),
                    style: context.strongTitleStyle.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    data.label,
                    style: context.captionMediumStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  const ExecutionCommitmentCard({
    super.key,
    required this.commitment,
    required this.onEdit,
    required this.onCreateAction,
    required this.onPause,
    required this.onResume,
    required this.onComplete,
    required this.onRecordProgress,
    this.openActionCount,
    this.blockedActionCount,
    this.busy = false,
  });

  final ExecutionCommitment commitment;
  final VoidCallback onEdit;
  final VoidCallback onCreateAction;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onComplete;
  final VoidCallback onRecordProgress;
  final int? openActionCount;
  final int? blockedActionCount;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
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
            child: _CommitmentBody(
              commitment: commitment,
              openActionCount: openActionCount,
              blockedActionCount: blockedActionCount,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          if (busy)
            const SizedBox(
              width: AppIconSizes.xl,
              height: AppIconSizes.xl,
              child: Center(
                child: FCircularProgress(size: FCircularProgressSizeVariant.xs),
              ),
            )
          else
            _LifecycleQuickButtons(
              canPause: commitment.status == ExecutionCommitmentStatus.active,
              canResume:
                  commitment.status == ExecutionCommitmentStatus.paused ||
                  commitment.status == ExecutionCommitmentStatus.completed ||
                  commitment.status == ExecutionCommitmentStatus.archived,
              canComplete:
                  commitment.status == ExecutionCommitmentStatus.active ||
                  commitment.status == ExecutionCommitmentStatus.paused,
              canCreateAction: commitment.status.isOpen,
              editTooltip: l10n.executionEditCommitmentTitle,
              onPause: onPause,
              onResume: onResume,
              onComplete: onComplete,
              onRecordProgress: onRecordProgress,
              onCreateAction: onCreateAction,
              onEdit: onEdit,
            ),
        ],
      ),
    );
  }
}

class _CommitmentBody extends StatelessWidget {
  const _CommitmentBody({
    required this.commitment,
    required this.openActionCount,
    required this.blockedActionCount,
  });

  final ExecutionCommitment commitment;
  final int? openActionCount;
  final int? blockedActionCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
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
        const SizedBox(height: AppSpacing.s10),
        Wrap(
          spacing: AppSpacing.s6,
          runSpacing: AppSpacing.s6,
          children: [
            AppBadge(
              label: executionCommitmentStatusLabel(l10n, commitment.status),
              tone: commitment.status == ExecutionCommitmentStatus.paused
                  ? AppBadgeTone.warning
                  : AppBadgeTone.info,
              size: AppBadgeSize.compact,
            ),
            AppBadge(
              label: executionHorizonLabel(l10n, commitment.horizon),
              size: AppBadgeSize.compact,
              icon: FLucideIcons.calendarClock,
            ),
            if (commitment.targetDate != null)
              AppBadge(
                label: l10n.executionTargetBadge(
                  executionDate(context, commitment.targetDate!),
                ),
                tone: AppBadgeTone.info,
                size: AppBadgeSize.compact,
                icon: FLucideIcons.calendarDays,
              ),
            ..._rollupBadges(
              l10n,
              openActionCount: openActionCount,
              blockedActionCount: blockedActionCount,
            ),
          ],
        ),
      ],
    );
  }
}

class ExecutionProjectCard extends StatelessWidget {
  const ExecutionProjectCard({
    super.key,
    required this.project,
    required this.onEdit,
    required this.onCreateAction,
    required this.onPause,
    required this.onResume,
    required this.onComplete,
    required this.onRecordProgress,
    this.openActionCount,
    this.blockedActionCount,
    this.busy = false,
  });

  final ExecutionProject project;
  final VoidCallback onEdit;
  final VoidCallback onCreateAction;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onComplete;
  final VoidCallback onRecordProgress;
  final int? openActionCount;
  final int? blockedActionCount;
  final bool busy;

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
            child: _ProjectBody(
              project: project,
              openActionCount: openActionCount,
              blockedActionCount: blockedActionCount,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          if (busy)
            const SizedBox(
              width: AppIconSizes.xl,
              height: AppIconSizes.xl,
              child: Center(
                child: FCircularProgress(size: FCircularProgressSizeVariant.xs),
              ),
            )
          else
            _LifecycleQuickButtons(
              canPause: project.status == ExecutionProjectStatus.active,
              canResume:
                  project.status == ExecutionProjectStatus.paused ||
                  project.status == ExecutionProjectStatus.completed ||
                  project.status == ExecutionProjectStatus.archived,
              canComplete:
                  project.status == ExecutionProjectStatus.active ||
                  project.status == ExecutionProjectStatus.paused,
              canCreateAction: project.status.isOpen,
              editTooltip: l10n.executionEditProjectTitle,
              onPause: onPause,
              onResume: onResume,
              onComplete: onComplete,
              onRecordProgress: onRecordProgress,
              onCreateAction: onCreateAction,
              onEdit: onEdit,
            ),
        ],
      ),
    );
  }
}

class _ProjectBody extends StatelessWidget {
  const _ProjectBody({
    required this.project,
    required this.openActionCount,
    required this.blockedActionCount,
  });

  final ExecutionProject project;
  final int? openActionCount;
  final int? blockedActionCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
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
            AppBadge(
              label: executionHorizonLabel(l10n, project.horizon),
              size: AppBadgeSize.compact,
              icon: FLucideIcons.calendarClock,
            ),
            if (project.targetDate != null)
              AppBadge(
                label: l10n.executionTargetBadge(
                  executionDate(context, project.targetDate!),
                ),
                tone: AppBadgeTone.info,
                size: AppBadgeSize.compact,
                icon: FLucideIcons.calendarDays,
              ),
            ..._rollupBadges(
              l10n,
              openActionCount: openActionCount,
              blockedActionCount: blockedActionCount,
            ),
          ],
        ),
      ],
    );
  }
}

List<Widget> _rollupBadges(
  AppLocalizations l10n, {
  required int? openActionCount,
  required int? blockedActionCount,
}) {
  return <Widget>[
    if (openActionCount != null)
      AppBadge(
        label: '${l10n.executionActionsSection}: $openActionCount',
        size: AppBadgeSize.compact,
        icon: FLucideIcons.listTodo,
      ),
    if (blockedActionCount != null && blockedActionCount > 0)
      AppBadge(
        label: '${l10n.executionOverviewBlocked}: $blockedActionCount',
        tone: AppBadgeTone.error,
        size: AppBadgeSize.compact,
        icon: FLucideIcons.octagonAlert,
      ),
  ];
}

class _LifecycleQuickButtons extends StatelessWidget {
  const _LifecycleQuickButtons({
    required this.canPause,
    required this.canResume,
    required this.canComplete,
    required this.canCreateAction,
    required this.editTooltip,
    required this.onPause,
    required this.onResume,
    required this.onComplete,
    required this.onRecordProgress,
    required this.onCreateAction,
    required this.onEdit,
  });

  final bool canPause;
  final bool canResume;
  final bool canComplete;
  final bool canCreateAction;
  final String editTooltip;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onComplete;
  final VoidCallback onRecordProgress;
  final VoidCallback onCreateAction;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final semantic = SemanticColors.of(context);
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      alignment: WrapAlignment.end,
      children: [
        if (canResume)
          AppIconButton(
            icon: FLucideIcons.play,
            tooltip: l10n.executionLifecycleResume,
            onPress: onResume,
            size: 32,
            iconSize: AppIconSizes.xs,
          )
        else if (canPause)
          AppIconButton(
            icon: FLucideIcons.pause,
            tooltip: l10n.executionLifecyclePause,
            onPress: onPause,
            size: 32,
            iconSize: AppIconSizes.xs,
          ),
        if (canComplete)
          AppIconButton(
            icon: FLucideIcons.check,
            tooltip: l10n.executionLifecycleComplete,
            onPress: onComplete,
            size: 32,
            iconSize: AppIconSizes.xs,
            iconColor: semantic.success,
            decoration: BoxDecoration(
              color: semantic.success.withValues(alpha: AppOpacity.subtle),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
        AppIconButton(
          icon: FLucideIcons.messageSquareText,
          tooltip: l10n.executionCreateProgressTitle,
          onPress: onRecordProgress,
          size: 32,
          iconSize: AppIconSizes.xs,
        ),
        if (canCreateAction)
          AppIconButton(
            icon: FLucideIcons.plus,
            tooltip: l10n.executionCreateActionTitle,
            onPress: onCreateAction,
            size: 32,
            iconSize: AppIconSizes.xs,
          ),
        AppIconButton(
          icon: FLucideIcons.pencil,
          tooltip: editTooltip,
          onPress: onEdit,
          size: 32,
          iconSize: AppIconSizes.xs,
          iconColor: colors.mutedForeground,
        ),
      ],
    );
  }
}

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
