part of 'execution_widgets.dart';

/// Compact task views with shared inline selection and visible counts.
class ExecutionOverviewStrip extends StatelessWidget {
  const ExecutionOverviewStrip({
    super.key,
    required this.snapshot,
    required this.selectedFilter,
    required this.onFilterChanged,
    this.inventoryAvailable = true,
  });

  final ExecutionOverviewSnapshot snapshot;
  final bool inventoryAvailable;
  final ExecutionTodayFilter selectedFilter;
  final ValueChanged<ExecutionTodayFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Keep the daily workspace to two actionable lenses. High-priority and
    // due counts are already represented on the action rows; showing them as
    // non-interactive chips here made the overview look like another filter
    // bar without offering a corresponding destination.
    return SegmentedRow<ExecutionTodayFilter>.inline(
      options: const <ExecutionTodayFilter>[
        ExecutionTodayFilter.today,
        ExecutionTodayFilter.blocked,
      ],
      value: selectedFilter,
      labelOf: (filter) => switch (filter) {
        ExecutionTodayFilter.today =>
          '${l10n.executionOverviewFocus} ${snapshot.todayCount}',
        ExecutionTodayFilter.blocked =>
          inventoryAvailable
              ? '${l10n.executionOverviewBlocked} ${snapshot.blockedCount}'
              : l10n.executionOverviewBlocked,
      },
      semanticLabelOf: (filter) => executionTodayFilterLabel(l10n, filter),
      onChanged: onFilterChanged,
    );
  }
}
