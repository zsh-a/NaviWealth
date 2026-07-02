/// Builds a [ContextPack] from already-aggregated state.
///
/// The compressor is intentionally pure: callers pass in scalar
/// inputs (numbers, strings, optional summaries) and get back a
/// fully-formed pack. The Riverpod-bound adapter that pulls these
/// inputs from feature providers lives separately so this layer has
/// no `core → features` import dependency.
///
/// Feature-layer adapters are responsible for pulling values out of Riverpod
/// and passing them through the typed parameters here. The downstream
/// [ContextPack.assertBudget] keeps the output well below the 16KB standard
/// tier even when every signal is present.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contracts/contracts.dart';

class ContextCompressor {
  const ContextCompressor();

  BaseContext compressBase({
    String? baseCurrency,
    AccountSummary accountSummary = const AccountSummary(
      totalCount: 0,
      byKind: <String, int>{},
    ),
    RiskPreference? riskPreference,
    FireGoalSummary? fireGoal,
  }) {
    final currency = baseCurrency ?? 'USD';
    return BaseContext(
      preferredCurrency: currency,
      // The feature-layer adapter (chat repository) passes the user's
      // declared appetite. The `?? moderate` is for direct callers without
      // access to that SSOT, e.g. unit tests exercising the compressor in
      // isolation.
      riskPreference: riskPreference ?? RiskPreference.moderate,
      accounts: accountSummary,
      // Keep the prompt grounding small here; richer cashflow detail
      // should come from explicit device tools when the turn needs it.
      cashflow: CashflowSummary(
        baseCurrency: currency,
        monthsCovered: 0,
        averageInflowMinor: '0',
        averageOutflowMinor: '0',
        trend: CashflowTrend.unknown,
      ),
      // Wired by the chat-repository adapter from firePlanProvider +
      // dashboard snapshot + the live FIRE projection scenario. `null`
      // is meaningful: it signals "plan not configured yet", and the
      // AI prompt treats that as "ask about FIRE goal setup".
      fireGoal: fireGoal,
    );
  }

  TaskContext compressTask({
    required RouteContext route,
    required IntentHint intent,
    double? expenseAnomalyDelta,
    int? depositMaturityCount,
    int? depositMaturityDays,
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
          summaryZh: '$depositMaturityCount 笔存款将在 $depositMaturityDays 天内到期',
        ),
      );
    }
    return TaskContext(
      route: route,
      intent: intent,
      signals: List<RecentSignal>.unmodifiable(signals),
    );
  }

  /// Build the full [ContextPack] and assert it fits the budget tier.
  /// Throws [ContextPackOversizeException] if it does not — callers
  /// should fall back to a smaller tier or omit signals.
  ContextPack compress({
    required RouteContext route,
    required IntentHint intent,
    String? baseCurrency,
    AccountSummary accountSummary = const AccountSummary(
      totalCount: 0,
      byKind: <String, int>{},
    ),
    double? expenseAnomalyDelta,
    int? depositMaturityCount,
    int? depositMaturityDays,
    PrivacyBudget budget = PrivacyBudget.standard,
    RiskPreference? riskPreference,
    FireGoalSummary? fireGoal,
  }) {
    final pack = ContextPack(
      version: kCurrentContextPackVersion,
      base: compressBase(
        baseCurrency: baseCurrency,
        accountSummary: accountSummary,
        riskPreference: riskPreference,
        fireGoal: fireGoal,
      ),
      task: compressTask(
        route: route,
        intent: intent,
        expenseAnomalyDelta: expenseAnomalyDelta,
        depositMaturityCount: depositMaturityCount,
        depositMaturityDays: depositMaturityDays,
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
