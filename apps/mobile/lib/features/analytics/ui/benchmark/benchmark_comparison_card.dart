import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../home/domain/dashboard_time_range.dart';
import '../../data/benchmark/benchmark_providers.dart';
import '../../domain/benchmark/benchmark_index.dart';
import 'benchmark_comparison_content.dart';
import 'benchmark_labels.dart';

/// Analytics-page card that compares the user's net-worth path against
/// one or more broad-base indices. Selection chips, range chips, the
/// comparison line chart, and the per-benchmark excess-return rows are
/// all stitched off of the providers in `benchmark_providers.dart`.
class BenchmarkComparisonCard extends ConsumerWidget {
  const BenchmarkComparisonCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final resultAsync = ref.watch(benchmarkComparisonResultProvider);

    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.benchmarkComparisonTitle,
              style: context.theme.typography.md,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.benchmarkComparisonSubtitle,
              style: context.theme.typography.sm.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 12),
            const _BenchmarkSelectionChips(),
            const SizedBox(height: 12),
            const _BenchmarkRangeChips(),
            const SizedBox(height: 16),
            resultAsync.when(
              loading: () => const BenchmarkCardSkeleton(),
              error: (e, _) => BenchmarkCardError(error: e),
              data: (result) => BenchmarkComparisonContent(result: result),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenchmarkSelectionChips extends ConsumerWidget {
  const _BenchmarkSelectionChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selection = ref.watch(benchmarkComparisonSelectionProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final index in BenchmarkIndex.values)
          FButton(
            variant: selection.contains(index)
                ? FButtonVariant.primary
                : FButtonVariant.outline,
            onPress: () {
              final next = [...selection];
              final isSelected = next.contains(index);
              if (isSelected) {
                if (next.length > 1) next.remove(index);
              } else {
                next.add(index);
              }
              ref.read(benchmarkComparisonSelectionProvider.notifier).state =
                  next;
            },
            child: Text(benchmarkLabel(l10n, index)),
          ),
      ],
    );
  }
}

class _BenchmarkRangeChips extends ConsumerWidget {
  const _BenchmarkRangeChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selected = ref.watch(benchmarkComparisonRangeProvider);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final preset in DashboardRangePreset.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FButton(
                variant: (preset == selected)
                    ? FButtonVariant.primary
                    : FButtonVariant.outline,
                onPress: () => _select(context, ref, preset),
                child: Text(_rangeLabel(l10n, preset)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    DashboardRangePreset preset,
  ) async {
    if (preset == DashboardRangePreset.custom) {
      await _pickCustomRange(context, ref);
      return;
    }
    ref.read(benchmarkComparisonCustomRangeProvider.notifier).state = null;
    ref.read(benchmarkComparisonRangeProvider.notifier).state = preset;
  }

  Future<void> _pickCustomRange(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final initialEnd =
        ref.read(benchmarkComparisonCustomRangeProvider)?.to ?? now;
    final initialStart =
        ref.read(benchmarkComparisonCustomRangeProvider)?.from ??
        now.subtract(const Duration(days: 365));
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    ref.read(benchmarkComparisonCustomRangeProvider.notifier).state = (
      from: picked.start,
      to: picked.end,
    );
    ref.read(benchmarkComparisonRangeProvider.notifier).state =
        DashboardRangePreset.custom;
  }

  String _rangeLabel(AppLocalizations l10n, DashboardRangePreset preset) {
    switch (preset) {
      case DashboardRangePreset.m1:
        return l10n.dashboardRange1M;
      case DashboardRangePreset.m3:
        return l10n.dashboardRange3M;
      case DashboardRangePreset.m6:
        return l10n.dashboardRange6M;
      case DashboardRangePreset.y1:
        return l10n.dashboardRange1Y;
      case DashboardRangePreset.y3:
        return l10n.dashboardRange3Y;
      case DashboardRangePreset.all:
        return l10n.dashboardRangeAll;
      case DashboardRangePreset.custom:
        return l10n.dashboardRangeCustom;
    }
  }
}
