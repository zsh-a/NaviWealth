part of 'execution_widgets.dart';

/// Compact overview: SegmentedRow lens + quiet meta chips.
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
    final status = context.appTheme.status;

    final meta = <_OverviewMeta>[
      if (snapshot.highPriorityCount > 0)
        _OverviewMeta(
          label: l10n.executionOverviewHigh,
          value: snapshot.highPriorityCount,
          icon: FLucideIcons.flag,
          color: status.warning.fg,
        ),
      if (snapshot.dueCount > 0)
        _OverviewMeta(
          label: l10n.executionOverviewDue,
          value: snapshot.dueCount,
          icon: FLucideIcons.calendarClock,
          color: colors.primary,
        ),
      if (snapshot.recentProgressCount > 0)
        _OverviewMeta(
          label: l10n.executionOverviewProgress7d,
          value: snapshot.recentProgressCount,
          icon: FLucideIcons.clipboardCheck,
          color: status.success.fg,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero rule (§8.1): every Today stage carries exactly one
        // display-scale number — for Execution, today's focus count.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${snapshot.todayCount}',
              style: TypographyTokens.displayLarge,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                l10n.executionOverviewFocus,
                style: context.mutedLabelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        AppAdaptiveChoice<ExecutionTodayFilter>(
          title: l10n.executionTodayTitle,
          options: ExecutionTodayFilter.values,
          value: selectedFilter,
          labelOf: (filter) => switch (filter) {
            ExecutionTodayFilter.focus =>
              '${l10n.executionOverviewFocus} ${snapshot.todayCount}',
            ExecutionTodayFilter.backlog =>
              '${l10n.executionOverviewBacklog} ${snapshot.backlogCount}',
            ExecutionTodayFilter.blocked =>
              '${l10n.executionOverviewBlocked} ${snapshot.blockedCount}',
            ExecutionTodayFilter.open =>
              '${l10n.executionOverviewOpen} ${snapshot.openCount}',
          },
          semanticLabelOf: (filter) => executionTodayFilterLabel(l10n, filter),
          iconOf: executionTodayFilterIcon,
          onChanged: onFilterChanged,
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: AppPageRhythm.row),
          Wrap(
            spacing: AppPageRhythm.row,
            runSpacing: AppPageRhythm.row,
            children: [
              for (final item in meta) _ExecutionOverviewMetaChip(data: item),
            ],
          ),
        ],
      ],
    );
  }
}

class _OverviewMeta {
  const _OverviewMeta({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _ExecutionOverviewMetaChip extends StatelessWidget {
  const _ExecutionOverviewMetaChip({required this.data});

  final _OverviewMeta data;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${data.label}: ${data.value}',
      child: AppBadge(
        icon: data.icon,
        label: '${data.label} ${data.value}',
        size: AppBadgeSize.compact,
        foregroundColor: data.color,
        containerColor: data.color.withValues(alpha: AppOpacity.light),
      ),
    );
  }
}
