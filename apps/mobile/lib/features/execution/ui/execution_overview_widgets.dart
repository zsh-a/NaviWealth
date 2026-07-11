part of 'execution_widgets.dart';

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
    final filters = <_OverviewTileData>[
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
    ];
    final summaries = <_OverviewTileData>[
      if (snapshot.activeProjectCount > 0)
        _OverviewTileData(
          label: l10n.executionOverviewProjects,
          value: snapshot.activeProjectCount,
          icon: FLucideIcons.folder,
          color: colors.primary,
        ),
      if (snapshot.activeCommitmentCount > 0)
        _OverviewTileData(
          label: l10n.executionOverviewCommitments,
          value: snapshot.activeCommitmentCount,
          icon: FLucideIcons.target,
          color: colors.primary,
        ),
      if (snapshot.recentProgressCount > 0)
        _OverviewTileData(
          label: l10n.executionOverviewProgress7d,
          value: snapshot.recentProgressCount,
          icon: FLucideIcons.clipboardCheck,
          color: semantic.success,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < filters.length; index++) ...[
                if (index > 0) const SizedBox(width: AppSpacing.s6),
                _ExecutionOverviewTile(
                  data: filters[index],
                  selected: filters[index].filter == selectedFilter,
                  onPress: () => onFilterChanged(filters[index].filter!),
                ),
              ],
            ],
          ),
        ),
        if (summaries.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s10),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              for (final summary in summaries)
                _ExecutionOverviewSummary(data: summary),
            ],
          ),
        ],
      ],
    );
  }
}

class _ExecutionOverviewSummary extends StatelessWidget {
  const _ExecutionOverviewSummary({required this.data});

  final _OverviewTileData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      label: '${data.label}: ${data.value}',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s6,
        ),
        decoration: BoxDecoration(
          color: colors.muted.withValues(alpha: AppOpacity.medium),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(data.icon, size: AppIconSizes.xs, color: data.color),
            const SizedBox(width: AppSpacing.s6),
            Text(
              '${data.label} ${data.value}',
              style: context.captionMediumStyle.copyWith(
                color: colors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
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
      button: true,
      child: FTappable(
        onPress: onPress,
        child: AnimatedContainer(
          duration: AppMotionPolicy.duration(context, Motion.fast),
          curve: Motion.standardDecelerate,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s10,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: AppOpacity.subtle)
                : colors.muted.withValues(alpha: AppOpacity.subtle),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: selected
                  ? colors.primary.withValues(alpha: AppOpacity.light)
                  : colors.border.withValues(alpha: AppOpacity.subtle),
              width: AppStroke.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(data.icon, size: AppIconSizes.xs, color: color),
              const SizedBox(width: AppSpacing.s6),
              Text(
                data.label,
                style: context.captionMediumStyle.copyWith(
                  color: selected ? colors.foreground : colors.mutedForeground,
                ),
              ),
              const SizedBox(width: AppSpacing.s6),
              Text(
                data.value.toString(),
                style: context.captionLabelStyle.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
