/// Builds a [ContextPack] from already-aggregated state.
///
/// The compressor is intentionally pure: callers pass in scalar
/// inputs (numbers, strings, optional summaries) and get back a
/// fully-formed pack. The Riverpod-bound adapter that pulls these
/// inputs from feature providers lives separately so this layer has
/// no `core → features` import dependency.
///
/// Phase 1 fills the inputs we already aggregate today (header
/// metrics, expense anomaly, deposit maturity) and leaves several
/// fields at safe defaults — see `TODO(phase2)` markers. The
/// downstream [ContextPack.assertBudget] keeps the output well below
/// the 16KB standard tier even when every signal is present.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts/contracts.dart';

class ContextCompressor {
  const ContextCompressor();

  BaseContext compressBase({String? baseCurrency}) {
    final currency = baseCurrency ?? 'USD';
    return BaseContext(
      preferredCurrency: currency,
      // TODO(phase2): wire to settings.riskPreference.
      riskPreference: RiskPreference.moderate,
      // TODO(phase2): aggregate from accounts repository.
      accounts: const AccountSummary(
        totalCount: 0,
        byKind: <String, int>{},
      ),
      // TODO(phase2): replace with real cashflow aggregation —
      // monthlyChangePct on the dashboard is net-worth delta, not
      // cashflow direction. Keeping `unknown` here is more honest
      // than treating the proxy as authoritative.
      cashflow: CashflowSummary(
        baseCurrency: currency,
        monthsCovered: 0,
        averageInflowMinor: '0',
        averageOutflowMinor: '0',
        trend: CashflowTrend.unknown,
      ),
      // TODO(phase2): integrate FIRE goal data.
      fireGoal: null,
    );
  }

  TaskContext compressTask({
    required RouteContext route,
    required IntentHint intent,
    double? expenseAnomalyDelta,
    int? depositMaturityCount,
    int? depositMaturityDays,
    FreshnessHint? freshnessHint,
    List<AnalyticalUpload> analyticalUploads = const <AnalyticalUpload>[],
    String? deviceHlc,
  }) {
    final signals = <RecentSignal>[];
    if (expenseAnomalyDelta != null) {
      final pct = (expenseAnomalyDelta * 100).round();
      signals.add(
        RecentSignal(
          kind: SignalKind.spendingSpike,
          severity: expenseAnomalyDelta > 0.5
              ? SignalSeverity.critical
              : SignalSeverity.warn,
          summaryZh: '本月支出预计较前 3 月平均高 $pct%',
        ),
      );
    }
    if (depositMaturityCount != null &&
        depositMaturityCount > 0 &&
        depositMaturityDays != null) {
      signals.add(
        RecentSignal(
          kind: SignalKind.depositMaturing,
          severity: SignalSeverity.info,
          summaryZh:
              '$depositMaturityCount 笔存款将在 $depositMaturityDays 天内到期',
        ),
      );
    }
    return TaskContext(
      route: route,
      intent: intent,
      signals: List<RecentSignal>.unmodifiable(signals),
      freshnessHint: freshnessHint,
      analyticalUploads: List<AnalyticalUpload>.unmodifiable(analyticalUploads),
      deviceHlc: deviceHlc,
    );
  }

  /// Build the full [ContextPack] and assert it fits the budget tier.
  /// Throws [ContextPackOversizeException] if it does not — callers
  /// should fall back to a smaller tier or omit signals.
  ContextPack compress({
    required RouteContext route,
    required IntentHint intent,
    String? baseCurrency,
    double? expenseAnomalyDelta,
    int? depositMaturityCount,
    int? depositMaturityDays,
    FreshnessHint? freshnessHint,
    List<AnalyticalUpload> analyticalUploads = const <AnalyticalUpload>[],
    String? deviceHlc,
    PrivacyBudget budget = PrivacyBudget.standard,
  }) {
    final pack = ContextPack(
      version: kCurrentContextPackVersion,
      base: compressBase(baseCurrency: baseCurrency),
      task: compressTask(
        route: route,
        intent: intent,
        expenseAnomalyDelta: expenseAnomalyDelta,
        depositMaturityCount: depositMaturityCount,
        depositMaturityDays: depositMaturityDays,
        freshnessHint: freshnessHint,
        analyticalUploads: analyticalUploads,
        deviceHlc: deviceHlc,
      ),
      budget: budget,
    );
    pack.assertBudget();
    return pack;
  }
}

/// Provider for the pure compressor. The Phase 2 adapter that pulls
/// dashboard / anomaly / maturity inputs and calls
/// [ContextCompressor.compress] will live next to its consumer (chat
/// repository) so this file stays decoupled from feature modules.
final contextCompressorProvider = Provider<ContextCompressor>(
  (ref) => const ContextCompressor(),
);
