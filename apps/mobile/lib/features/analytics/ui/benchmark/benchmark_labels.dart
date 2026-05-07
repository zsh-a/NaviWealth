import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/benchmark/benchmark_index.dart';

/// Localized label for [index]. Shared by benchmark chips, chart legends,
/// and summary rows so they cannot drift.
String benchmarkLabel(AppLocalizations l10n, BenchmarkIndex index) {
  switch (index) {
    case BenchmarkIndex.hs300:
      return l10n.benchmarkIndexHs300;
    case BenchmarkIndex.sp500:
      return l10n.benchmarkIndexSp500;
    case BenchmarkIndex.nasdaq:
      return l10n.benchmarkIndexNasdaq;
    case BenchmarkIndex.hsi:
      return l10n.benchmarkIndexHsi;
  }
}
