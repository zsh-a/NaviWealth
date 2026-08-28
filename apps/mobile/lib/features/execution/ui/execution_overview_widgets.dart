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
    // Keep the daily workspace to two actionable lenses. High-priority and
    // due counts are already represented on the action rows; showing them as
    // non-interactive chips here made the overview look like another filter
    // bar without offering a corresponding destination.
    return AppAdaptiveChoice<ExecutionTodayFilter>(
      title: l10n.executionTodayTitle,
      options: const <ExecutionTodayFilter>[
        ExecutionTodayFilter.today,
        ExecutionTodayFilter.blocked,
      ],
      value: selectedFilter,
      labelOf: (filter) => switch (filter) {
        ExecutionTodayFilter.today =>
          '${l10n.executionOverviewFocus} ${snapshot.todayCount}',
        ExecutionTodayFilter.blocked =>
          '${l10n.executionOverviewBlocked} ${snapshot.blockedCount}',
      },
      semanticLabelOf: (filter) => executionTodayFilterLabel(l10n, filter),
      iconOf: executionTodayFilterIcon,
      onChanged: onFilterChanged,
    );
  }
}
