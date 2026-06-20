import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/rebalance/data/rebalance_drift_insight_provider.dart';
import 'package:naviwealth/features/rebalance/data/rebalance_providers.dart';
import 'package:naviwealth/features/rebalance/domain/rebalance_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('summarizeRebalanceDrift', () {
    test('returns null when no drift crosses the warning threshold', () {
      final summary = summarizeRebalanceDrift(
        _plan([
          _drift(AssetCategory.cash, actual: 0.53, target: 0.5),
          _drift(AssetCategory.stock, actual: 0.27, target: 0.3),
        ]),
        threshold: 0.05,
      );

      expect(summary, isNull);
    });

    test('selects the largest absolute drift and keeps its sign', () {
      final summary = summarizeRebalanceDrift(
        _plan([
          _drift(AssetCategory.cash, actual: 0.62, target: 0.5),
          _drift(AssetCategory.stock, actual: 0.18, target: 0.4),
        ]),
        threshold: 0.05,
      );

      expect(summary, isNotNull);
      expect(summary!.category, AssetCategory.stock);
      expect(summary.deviation, closeTo(-0.22, 0.0001));
    });
  });

  test('rebalanceDriftInsightProvider honors persisted threshold', () async {
    SharedPreferences.setMockInitialValues({
      'naviwealth.rebalance.warning_threshold': 0.2,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        rebalancePlanProvider.overrideWithValue(
          _plan([
            _drift(AssetCategory.cash, actual: 0.66, target: 0.5),
            _drift(AssetCategory.stock, actual: 0.14, target: 0.4),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final summary = container.read(rebalanceDriftInsightProvider);

    expect(summary, isNotNull);
    expect(summary!.category, AssetCategory.stock);
    expect(summary.deviation, closeTo(-0.26, 0.0001));
  });
}

RebalancePlan _plan(List<Drift> drifts) => RebalancePlan(
  target: TargetAllocation(
    weights: {
      for (final category in AssetCategory.values)
        if (category != AssetCategory.liability) category: 0,
      AssetCategory.cash: 1,
    },
  ),
  actualWeights: const {},
  drifts: drifts,
  trades: const [],
  estimatedFees: Money.zero('USD'),
  estimatedTaxes: Money.zero('USD'),
  driftBeforePct: 0,
  driftAfterPct: 0,
  totalAssets: Money(Decimal.parse('1000'), 'USD'),
);

Drift _drift(
  AssetCategory category, {
  required double actual,
  required double target,
}) => Drift(
  category: category,
  actualWeight: actual,
  targetWeight: target,
  severity: DriftSeverity.warning,
);
