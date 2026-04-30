import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/data/dashboard_providers.dart';
import '../domain/fire_calculator.dart';
import '../domain/fire_projection.dart';
import 'fire_goal_preferences.dart';

/// User's actual annualized return, sourced from FIR-55's XIRR engine when
/// the production wiring lands. Keeping it as a stand-alone provider lets
/// the dashboard add a "Live (XIRR)" scenario as soon as the value is
/// non-null — and it stays out of the way (no dotted line, neutral becomes
/// the sensitivity baseline) until then.
///
/// Override at the provider scope or in tests; production wiring will
/// supply a `Provider<double?>` that watches the user's portfolio XIRR
/// across the trailing 1Y window.
final fireLiveAnnualReturnProvider = Provider<double?>((ref) => null);

/// Stateless calculator instance. Cheap to construct so this is mostly for
/// tests — but isolating it lets future PRs swap in a different scenario
/// rate set without touching the dashboard widgets.
final fireCalculatorProvider = Provider<FireCalculator>(
  (ref) => const FireCalculator(),
);

/// The fully-built FIRE dashboard view. Recomputes when the goal,
/// dashboard snapshot (current net worth), or live XIRR rate changes.
///
/// Returns [AsyncValue] so the dashboard can render the dashboard
/// snapshot's loading / error state alongside the FIRE-specific empty
/// state (no goal yet → [FireDashboardView.progressRatio] is null).
final fireDashboardViewProvider =
    Provider<AsyncValue<FireDashboardView>>((ref) {
  final goal = ref.watch(fireGoalProvider);
  final snapshotAsync = ref.watch(dashboardSnapshotProvider);
  final liveRate = ref.watch(fireLiveAnnualReturnProvider);
  final calculator = ref.watch(fireCalculatorProvider);
  final baseCurrency = ref.watch(dashboardBaseCurrencyProvider);

  return snapshotAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (snapshot) {
      final currentNetWorth =
          snapshot.isEmpty ? Decimal.zero : snapshot.netWorth.amount;
      final view = calculator.buildView(
        goal: goal,
        currentNetWorth: currentNetWorth,
        baseCurrency: baseCurrency,
        start: DateTime.now(),
        liveAnnualReturn: liveRate,
      );
      return AsyncValue.data(view);
    },
  );
});

