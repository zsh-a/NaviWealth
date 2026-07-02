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
