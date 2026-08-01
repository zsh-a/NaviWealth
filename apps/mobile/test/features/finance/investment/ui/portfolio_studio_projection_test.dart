import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/investment/domain/allocation/portfolio_allocation_tree.dart';
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_capital_assignment.dart';
import 'package:naviwealth/features/finance/investment/domain/portfolio_trend.dart';
import 'package:naviwealth/features/finance/investment/domain/strategy/portfolio_strategy.dart';
import 'package:naviwealth/features/finance/investment/ui/portfolio_studio_projection.dart';
import 'package:naviwealth/features/finance/rebalance/domain/portfolio_rebalance_group.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'user',
  updatedAt: DateTime.utc(2026, 8, 2),
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);

const _root = AllocationNode(
  id: 'plan',
  parentId: null,
  type: AllocationNodeType.plan,
  name: 'Plan',
  targetWeightBps: 10000,
  driftBandBps: 0,
  transferPolicy: GroupTransferPolicy.bidirectional,
);

const _fromPortfolio = AllocationNode(
  id: 'portfolio:from',
  parentId: 'plan',
  type: AllocationNodeType.portfolio,
  name: 'From portfolio node',
  targetWeightBps: 5000,
  driftBandBps: 500,
  transferPolicy: GroupTransferPolicy.bidirectional,
  referenceId: 'from',
);

const _toPortfolio = AllocationNode(
  id: 'portfolio:to',
  parentId: 'plan',
  type: AllocationNodeType.portfolio,
  name: 'To portfolio node',
  targetWeightBps: 5000,
  driftBandBps: 500,
  transferPolicy: GroupTransferPolicy.bidirectional,
  referenceId: 'to',
);

const _fromSleeve = AllocationNode(
  id: 'sleeve:from-core',
  parentId: 'portfolio:from',
  type: AllocationNodeType.sleeve,
  name: 'From core',
  targetWeightBps: 10000,
  driftBandBps: 500,
  transferPolicy: GroupTransferPolicy.bidirectional,
  referenceId: 'from-core',
);

const _toSleeve = AllocationNode(
  id: 'sleeve:to-core',
  parentId: 'portfolio:to',
  type: AllocationNodeType.sleeve,
  name: 'To core',
  targetWeightBps: 10000,
  driftBandBps: 500,
  transferPolicy: GroupTransferPolicy.bidirectional,
  referenceId: 'to-core',
);

PortfolioStrategyConfig _strategy(String id) => PortfolioStrategyConfig(
  id: id,
  portfolioId: 'from',
  kind: PortfolioStrategyKind.indexCore,
  schemaVersion: 1,
  enabled: true,
  capitalRole: StrategyCapitalRole.overlay,
  rebalanceGroupId: 'from-core',
  settings: const IndexCoreStrategySettings(automaticContributions: false),
  sync: _meta(),
);

PortfolioCapitalAssignment _assignment(String id) => PortfolioCapitalAssignment(
  id: id,
  portfolioId: 'from',
  rebalanceGroupId: 'from-core',
  sourceKind: PortfolioCapitalSourceKind.lot,
  sourceId: 'lot:$id',
  quantity: null,
  amount: null,
  currency: null,
  assignedAt: DateTime.utc(2026, 8, 2),
  sync: _meta(),
);

PortfolioTrendPoint _trendPoint({
  required int day,
  required String value,
  required double performance,
}) => PortfolioTrendPoint(
  asOf: DateTime.utc(2026, 7, day),
  marketValueInBase: Decimal.parse(value),
  costBasisInBase: Decimal.zero,
  cashValueInBase: Decimal.zero,
  netFlowInBase: Decimal.zero,
  performanceRatio: performance,
  quality: PortfolioTrendQuality.complete,
);

void main() {
  group('portfolio trend chart projection', () {
    test('drops only leading unfunded samples and converts performance', () {
      final leadingZero = _trendPoint(day: 1, value: '0', performance: 0);
      final funded = _trendPoint(day: 2, value: '100', performance: 0.125);
      final laterZero = _trendPoint(day: 3, value: '0', performance: -0.25);
      final projection = PortfolioTrendChartProjection.fromSeries(
        series: PortfolioTrendSeries(
          portfolioId: 'portfolio',
          baseCurrency: 'USD',
          range: PortfolioTrendRange.month,
          points: [leadingZero, funded, laterZero],
        ),
        metric: PortfolioTrendMetric.performance,
      );

      expect(projection.data, hasLength(2));
      expect(projection.data.first.source, same(funded));
      expect(projection.data.first.value, 12.5);
      expect(projection.data.last.source, same(laterZero));
      expect(projection.data.last.value, -25);
      expect(
        projection.axisGranularity,
        PortfolioTrendAxisGranularity.dayMonth,
      );
      expect(projection.isDown, isTrue);
      expect(projection.isRenderable, isTrue);
    });

    test('keeps market values and maps longer-range axis granularity', () {
      final first = _trendPoint(day: 1, value: '100.25', performance: 0);
      final projection = PortfolioTrendChartProjection.fromSeries(
        series: PortfolioTrendSeries(
          portfolioId: 'portfolio',
          baseCurrency: 'USD',
          range: PortfolioTrendRange.year,
          points: [first],
        ),
        metric: PortfolioTrendMetric.marketValue,
      );

      expect(projection.data.single.value, 100.25);
      expect(
        projection.axisGranularity,
        PortfolioTrendAxisGranularity.monthYear,
      );
      expect(projection.isDown, isFalse);
      expect(projection.isRenderable, isFalse);
    });

    test('uses year-only granularity for all-time series', () {
      final projection = PortfolioTrendChartProjection.fromSeries(
        series: const PortfolioTrendSeries(
          portfolioId: 'portfolio',
          baseCurrency: 'USD',
          range: PortfolioTrendRange.all,
          points: [],
        ),
        metric: PortfolioTrendMetric.marketValue,
      );

      expect(projection.data, isEmpty);
      expect(
        projection.axisGranularity,
        PortfolioTrendAxisGranularity.yearOnly,
      );
    });
  });

  test('studio summary counts inclusions and secondary rules by sleeve', () {
    final primary = _strategy('primary');
    final secondary = _strategy('secondary');
    final tree = PortfolioAllocationTree(
      root: _root,
      nodes: const [_root, _fromPortfolio, _fromSleeve, _toSleeve],
      attachments: [
        StrategyAttachment(
          id: primary.id,
          sleeveId: _fromSleeve.id,
          kind: primary.kind,
          enabled: true,
          isPrimary: true,
          config: primary,
        ),
        StrategyAttachment(
          id: secondary.id,
          sleeveId: _fromSleeve.id,
          kind: secondary.kind,
          enabled: true,
          isPrimary: false,
          config: secondary,
        ),
      ],
      inclusions: [
        CapitalInclusion(
          id: 'assignment-1',
          sleeveId: _fromSleeve.id,
          assignment: _assignment('assignment-1'),
        ),
        CapitalInclusion(
          id: 'assignment-2',
          sleeveId: _fromSleeve.id,
          assignment: _assignment('assignment-2'),
        ),
      ],
    );

    final summary = PortfolioStudioSummary.fromTree(
      tree: tree,
      sleeves: const [_fromSleeve, _toSleeve],
    );

    expect(summary.sleeveCount, 2);
    expect(summary.includedAssetCount, 2);
    expect(summary.secondaryRuleCount, 1);
  });

  test('transfer task resolves group labels and target default', () {
    const tree = PortfolioAllocationTree(
      root: _root,
      nodes: [_root, _fromPortfolio, _toPortfolio, _fromSleeve, _toSleeve],
      attachments: [],
      inclusions: [],
    );

    final task = PortfolioTransferTaskProjection.fromIntent(
      intent: const CapitalTransferIntent(
        fromPortfolioId: 'from',
        toPortfolioId: 'to',
        amount: '1250.50',
        currency: 'USD',
        fromGroupId: 'from-core',
      ),
      tree: tree,
      portfolioNames: const {'from': 'Source', 'to': 'Destination'},
    );

    expect(task.fromName, 'From core');
    expect(task.toName, 'Destination');
    expect(task.amount, Decimal.parse('1250.50'));
    expect(task.preferredGroupId, 'to-core');
  });

  test('transfer task preserves unknown ids and invalid amount state', () {
    const tree = PortfolioAllocationTree(
      root: _root,
      nodes: [_root],
      attachments: [],
      inclusions: [],
    );

    final task = PortfolioTransferTaskProjection.fromIntent(
      intent: const CapitalTransferIntent(
        fromPortfolioId: 'missing-from',
        toPortfolioId: 'missing-to',
        amount: 'not-an-amount',
        currency: 'USD',
        fromGroupId: 'missing-group',
        toGroupId: 'explicit-target',
      ),
      tree: tree,
      portfolioNames: const {},
    );

    expect(task.fromName, 'missing-group');
    expect(task.toName, 'explicit-target');
    expect(task.amount, isNull);
    expect(task.preferredGroupId, 'explicit-target');
  });
}
