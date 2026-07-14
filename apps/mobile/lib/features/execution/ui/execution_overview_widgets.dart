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
    final semantic = SemanticColors.of(context);

    final meta = <_OverviewMeta>[
      if (snapshot.highPriorityCount > 0)
        _OverviewMeta(
          label: l10n.executionOverviewHigh,
          value: snapshot.highPriorityCount,
          icon: FLucideIcons.flag,
          color: semantic.warning,
        ),
      if (snapshot.dueCount > 0)
        _OverviewMeta(
          label: l10n.executionOverviewDue,
          value: snapshot.dueCount,
          icon: FLucideIcons.calendarClock,
          color: colors.primary,
        ),
      if (snapshot.activeProjectCount > 0)
        _OverviewMeta(
          label: l10n.executionOverviewProjects,
          value: snapshot.activeProjectCount,
          icon: FLucideIcons.folder,
          color: colors.primary,
        ),
      if (snapshot.activeCommitmentCount > 0)
        _OverviewMeta(
          label: l10n.executionOverviewCommitments,
          value: snapshot.activeCommitmentCount,
          icon: FLucideIcons.target,
          color: colors.primary,
        ),
      if (snapshot.recentProgressCount > 0)
        _OverviewMeta(
          label: l10n.executionOverviewProgress7d,
          value: snapshot.recentProgressCount,
          icon: FLucideIcons.clipboardCheck,
          color: semantic.success,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedRow<ExecutionTodayFilter>(
          options: ExecutionTodayFilter.values,
          value: selectedFilter,
          labelOf: (filter) => switch (filter) {
            ExecutionTodayFilter.focus =>
              '${l10n.executionOverviewFocus} ${snapshot.todayCount}',
            ExecutionTodayFilter.blocked =>
              '${l10n.executionOverviewBlocked} ${snapshot.blockedCount}',
            ExecutionTodayFilter.open =>
              '${l10n.executionOverviewOpen} ${snapshot.openCount}',
          },
          iconOf: executionTodayFilterIcon,
          onChanged: (filter) {
            AppInteraction.signal(AppInteractionIntent.select);
            onFilterChanged(filter);
          },
          minSegmentWidth: 88,
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s10),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
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
