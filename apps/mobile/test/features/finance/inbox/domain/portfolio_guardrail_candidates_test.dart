import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/analytics/domain/concentration_risk.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/home/domain/dashboard_models.dart';
import 'package:naviwealth/features/finance/inbox/domain/financial_inbox.dart';
import 'package:naviwealth/features/finance/inbox/domain/portfolio_guardrail_candidates.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_engine.dart';
import 'package:naviwealth/features/finance/rebalance/domain/rebalance_models.dart';

void main() {
  const mapper = PortfolioGuardrailCandidates();

  group('fromConcentrationAlerts', () {
    test('maps warning and critical alerts to stable candidates', () {
      final alerts = [
        ConcentrationAlert(
          dimension: RiskDimension.asset,
          severity: RiskSeverity.critical,
          label: 'AAPL',
          weight: 0.42,
          threshold: 0.20,
          valueInBase: Decimal.parse('42000'),
          assetIds: const ['aapl'],
        ),
        ConcentrationAlert(
          dimension: RiskDimension.sector,
          severity: RiskSeverity.warning,
          label: 'Technology',
          weight: 0.38,
          threshold: 0.35,
          valueInBase: Decimal.parse('38000'),
          assetIds: const ['aapl', 'msft'],
        ),
      ];

      final candidates = mapper.fromConcentrationAlerts(alerts);

      expect(candidates, hasLength(2));

      final asset = candidates.firstWhere(
        (c) => c.sourceKey == 'concentration:asset:aapl',
      );
      expect(asset.kind, FinancialInboxKind.concentrationRisk);
      expect(asset.priority, FinancialInboxPriority.important);
      expect(asset.count, 1);
      expect(asset.route, FinanceRoutes.wealthPortfolio);
      expect(asset.evidence['dimension'], 'asset');
      expect(asset.evidence['label'], 'AAPL');
      expect(asset.evidence['weight'], 0.42);
      expect(asset.evidence['threshold'], 0.20);
      expect(asset.evidence['severity'], 'critical');
      expect(asset.evidence['asset_ids'], ['aapl']);

      final sector = candidates.firstWhere(
        (c) => c.sourceKey == 'concentration:sector:technology',
      );
      expect(sector.priority, FinancialInboxPriority.attention);
      expect(sector.route, FinanceRoutes.wealthPortfolio);
      expect(sector.evidence['label'], 'Technology');
    });

    test('returns empty when no concentration breaches', () {
      expect(mapper.fromConcentrationAlerts(const []), isEmpty);
    });

    test('sourceKey is stable for the same dimension and label', () {
      final a = ConcentrationAlert(
        dimension: RiskDimension.currency,
        severity: RiskSeverity.warning,
        label: 'CNY',
        weight: 0.55,
        threshold: 0.50,
        valueInBase: Decimal.zero,
        assetIds: const ['cash'],
      );
      final b = ConcentrationAlert(
        dimension: RiskDimension.currency,
        severity: RiskSeverity.critical,
        label: 'CNY',
        weight: 0.80,
        threshold: 0.50,
        valueInBase: Decimal.zero,
        assetIds: const ['cash', 'bond'],
      );

      final first = mapper.fromConcentrationAlerts([a]).single.sourceKey;
      final second = mapper.fromConcentrationAlerts([b]).single.sourceKey;
      expect(first, second);
      expect(first, 'concentration:currency:cny');
    });
  });

  group('fromRebalancePlan', () {
    test('emits rebalance-drift when asset targets drift past warning', () {
      final plan = const RebalanceEngine().compute(
        snapshot: _driftedSnapshot(),
        target: _assetTargetAllocation(),
      );

      final candidates = mapper.fromRebalancePlan(plan);

      expect(candidates, hasLength(1));
      final signal = candidates.single;
      expect(
        signal.sourceKey,
        PortfolioGuardrailCandidates.rebalanceDriftSourceKey,
      );
      expect(signal.kind, FinancialInboxKind.rebalanceDrift);
      expect(signal.route, FinanceRoutes.planRebalance);
      expect(signal.count, greaterThan(0));
      expect(
        signal.priority,
        anyOf(
          FinancialInboxPriority.attention,
          FinancialInboxPriority.important,
        ),
      );
      expect(signal.evidence['breach_count'], signal.count);
      expect(signal.evidence['max_abs_deviation'], isA<double>());
      expect(
        (signal.evidence['max_abs_deviation']! as double),
        greaterThanOrEqualTo(0.05),
      );
    });

    test('returns empty when under rebalance warning threshold', () {
      final plan = const RebalanceEngine().compute(
        snapshot: _balancedSnapshot(),
        target: _assetTargetAllocation(),
      );

      expect(mapper.fromRebalancePlan(plan), isEmpty);
      expect(plan.isBalanced, isTrue);
    });

    test('returns empty when only category targets exist (no asset targets)', () {
      final plan = const RebalanceEngine().compute(
        snapshot: _driftedSnapshot(),
        target: const TargetAllocation(
          weights: {
            AssetCategory.stock: 0.30,
            AssetCategory.etf: 0.40,
            AssetCategory.bondsAndFunds: 0.0,
            AssetCategory.cash: 0.30,
            AssetCategory.crypto: 0.0,
            AssetCategory.realEstate: 0.0,
            AssetCategory.vehicle: 0.0,
          },
        ),
      );

      // Category-only targets may show drift, but guardrail requires asset targets.
      expect(plan.drifts.any((d) => d.severity != DriftSeverity.ok), isTrue);
      expect(mapper.fromRebalancePlan(plan), isEmpty);
    });

    test('returns empty for null plan', () {
      expect(mapper.fromRebalancePlan(null), isEmpty);
    });

    test('critical asset drift raises important priority', () {
      // 80% QQQ vs 40% target → 40pp deviation > critical 10%.
      final plan = const RebalanceEngine().compute(
        snapshot: DashboardSnapshot(
          asOf: DateTime.utc(2026, 7, 1),
          baseCurrency: 'USD',
          allocations: [
            CategoryAllocation(
              category: AssetCategory.etf,
              totalInBase: Money(Decimal.parse('800'), 'USD'),
              items: [
                CategoryItem(
                  id: 'qqq',
                  name: 'QQQ',
                  subtitle: null,
                  valueInBase: Money(Decimal.parse('800'), 'USD'),
                  nativeAmount: Decimal.parse('800'),
                  nativeCurrency: 'USD',
                ),
              ],
            ),
            CategoryAllocation(
              category: AssetCategory.cash,
              totalInBase: Money(Decimal.parse('200'), 'USD'),
              items: [
                CategoryItem(
                  id: 'cash',
                  name: 'Cash',
                  subtitle: null,
                  valueInBase: Money(Decimal.parse('200'), 'USD'),
                  nativeAmount: Decimal.parse('200'),
                  nativeCurrency: 'USD',
                ),
              ],
            ),
          ],
          totalAssets: Money(Decimal.parse('1000'), 'USD'),
          totalLiabilities: Money.zero('USD'),
          netWorth: Money(Decimal.parse('1000'), 'USD'),
        ),
        target: const TargetAllocation(
          weights: {
            AssetCategory.stock: 0,
            AssetCategory.etf: 0,
            AssetCategory.bondsAndFunds: 0,
            AssetCategory.cash: 0.60,
            AssetCategory.crypto: 0,
            AssetCategory.realEstate: 0,
            AssetCategory.vehicle: 0,
          },
          assetTargets: {
            'qqq': AssetTargetAllocation(
              assetId: 'qqq',
              label: 'QQQ',
              category: AssetCategory.etf,
              weight: 0.40,
            ),
          },
        ),
      );

      final signal = mapper.fromRebalancePlan(plan).single;
      expect(signal.priority, FinancialInboxPriority.important);
      expect(signal.sourceKey, 'rebalance-drift');
      expect(signal.route, FinanceRoutes.planRebalance);
    });
  });

  group('sourceKey helpers', () {
    test('concentrationSourceKey normalizes whitespace', () {
      expect(
        PortfolioGuardrailCandidates.concentrationSourceKey(
          RiskDimension.sector,
          '  Consumer Staples  ',
        ),
        'concentration:sector:consumer-staples',
      );
    });
  });
}

/// QQQ 70% / residual ETF 10% / cash 20% with QQQ target 40% → material drift.
DashboardSnapshot _driftedSnapshot() => DashboardSnapshot(
  asOf: DateTime.utc(2026, 7, 1),
  baseCurrency: 'USD',
  allocations: [
    CategoryAllocation(
      category: AssetCategory.etf,
      totalInBase: Money(Decimal.parse('800'), 'USD'),
      items: [
        CategoryItem(
          id: 'qqq',
          name: 'QQQ',
          subtitle: null,
          valueInBase: Money(Decimal.parse('700'), 'USD'),
          nativeAmount: Decimal.parse('700'),
          nativeCurrency: 'USD',
        ),
        CategoryItem(
          id: 'voo',
          name: 'VOO',
          subtitle: null,
          valueInBase: Money(Decimal.parse('100'), 'USD'),
          nativeAmount: Decimal.parse('100'),
          nativeCurrency: 'USD',
        ),
      ],
    ),
    CategoryAllocation(
      category: AssetCategory.cash,
      totalInBase: Money(Decimal.parse('200'), 'USD'),
      items: [
        CategoryItem(
          id: 'cash',
          name: 'Cash',
          subtitle: null,
          valueInBase: Money(Decimal.parse('200'), 'USD'),
          nativeAmount: Decimal.parse('200'),
          nativeCurrency: 'USD',
        ),
      ],
    ),
  ],
  totalAssets: Money(Decimal.parse('1000'), 'USD'),
  totalLiabilities: Money.zero('USD'),
  netWorth: Money(Decimal.parse('1000'), 'USD'),
);

/// Matches asset + residual targets within the default ±5% warning band.
DashboardSnapshot _balancedSnapshot() => DashboardSnapshot(
  asOf: DateTime.utc(2026, 7, 1),
  baseCurrency: 'USD',
  allocations: [
    CategoryAllocation(
      category: AssetCategory.etf,
      totalInBase: Money(Decimal.parse('400'), 'USD'),
      items: [
        CategoryItem(
          id: 'qqq',
          name: 'QQQ',
          subtitle: null,
          valueInBase: Money(Decimal.parse('400'), 'USD'),
          nativeAmount: Decimal.parse('400'),
          nativeCurrency: 'USD',
        ),
      ],
    ),
    CategoryAllocation(
      category: AssetCategory.cash,
      totalInBase: Money(Decimal.parse('600'), 'USD'),
      items: [
        CategoryItem(
          id: 'cash',
          name: 'Cash',
          subtitle: null,
          valueInBase: Money(Decimal.parse('600'), 'USD'),
          nativeAmount: Decimal.parse('600'),
          nativeCurrency: 'USD',
        ),
      ],
    ),
  ],
  totalAssets: Money(Decimal.parse('1000'), 'USD'),
  totalLiabilities: Money.zero('USD'),
  netWorth: Money(Decimal.parse('1000'), 'USD'),
);

TargetAllocation _assetTargetAllocation() => const TargetAllocation(
  weights: {
    AssetCategory.stock: 0,
    AssetCategory.etf: 0,
    AssetCategory.bondsAndFunds: 0,
    AssetCategory.cash: 0.60,
    AssetCategory.crypto: 0,
    AssetCategory.realEstate: 0,
    AssetCategory.vehicle: 0,
  },
  assetTargets: {
    'qqq': AssetTargetAllocation(
      assetId: 'qqq',
      label: 'QQQ',
      category: AssetCategory.etf,
      weight: 0.40,
    ),
  },
);
