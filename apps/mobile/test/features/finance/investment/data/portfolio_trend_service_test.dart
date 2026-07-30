import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/investment/data/portfolio_trend_service.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/investment_portfolio.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/domain/models/portfolio_capital_assignment.dart';
import 'package:naviwealth/features/finance/investment/domain/portfolio_trend.dart';

Decimal _d(String value) => Decimal.parse(value);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'user',
  updatedAt: DateTime.utc(2026, 6, 30),
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);

InvestmentPortfolio _portfolio(String id) => InvestmentPortfolio(
  id: id,
  name: id,
  baseCurrency: 'USD',
  goalId: null,
  color: null,
  createdAt: DateTime.utc(2026, 6, 30),
  archived: false,
  sync: _meta(),
);

PortfolioCapitalAssignment _assignment({
  required String id,
  required String portfolioId,
  required DateTime assignedAt,
  DateTime? unassignedAt,
}) {
  return PortfolioCapitalAssignment(
    id: id,
    portfolioId: portfolioId,
    rebalanceGroupId: 'group-$portfolioId',
    sourceKind: PortfolioCapitalSourceKind.lot,
    sourceId: 'lot',
    quantity: null,
    amount: null,
    currency: null,
    assignedAt: assignedAt,
    unassignedAt: unassignedAt,
    sync: _meta(),
  );
}

class _SameCurrencyConverter implements CurrencyConverter {
  const _SameCurrencyConverter();

  @override
  Money convert(Money amount, String to, {DateTime? on}) {
    if (amount.currency != to) {
      throw FxRateNotFoundError(amount.currency, to, on);
    }
    return amount;
  }
}

class _SampledHoldings implements SampledHoldingService {
  const _SampledHoldings({this.growsOnLastDay = false});

  final bool growsOnLastDay;

  Lot get lot => Lot(
    id: 'lot',
    openingTransactionId: 'trade',
    accountId: 'broker',
    assetId: 'asset',
    currency: 'USD',
    originalQuantity: _d('10'),
    remainingQuantity: _d('10'),
    costPerUnit: _d('100'),
    openedAt: DateTime.utc(2026, 6, 1),
  );

  HoldingSample _sample(DateTime asOf) {
    final unitPrice =
        growsOnLastDay && asOf.year == 2026 && asOf.month == 7 && asOf.day == 30
        ? _d('110')
        : _d('100');
    final value = unitPrice * _d('10');
    return HoldingSample(
      asOf: asOf.toUtc(),
      lots: [lot],
      snapshots: {
        'asset': HoldingSnapshot(
          assetId: 'asset',
          quantity: _d('10'),
          costBasisInAssetCurrency: _d('1000'),
          marketValueInAssetCurrency: value,
          assetCurrency: 'USD',
          costBasisInBase: _d('1000'),
          marketValueInBase: value,
          unrealizedPnlInBase: value - _d('1000'),
          weight: Decimal.one,
          baseCurrency: 'USD',
          asOf: asOf,
          unitPriceInAssetCurrency: unitPrice,
        ),
      },
    );
  }

  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async =>
      _sample(asOf).snapshots;

  @override
  Future<List<HoldingSample>> computeAtSamples(
    Iterable<DateTime> dates,
  ) async => dates.map(_sample).toList(growable: false);

  @override
  Future<void> invalidateFrom(DateTime from) async {}

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) async => [lot];

  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) async =>
      LotInventorySnapshot(ownerUserId: 'user', day: day, lots: [lot]);
}

void main() {
  const converter = _SameCurrencyConverter();
  final end = DateTime.utc(2026, 7, 30, 12);

  test('builds a cash-flow-adjusted portfolio value series', () async {
    const service = PortfolioTrendService(
      holdings: _SampledHoldings(growsOnLastDay: true),
      converter: converter,
      baseCurrency: 'USD',
    );

    final result = await service.computeMany(
      portfolios: [_portfolio('income')],
      assignmentHistory: [
        _assignment(
          id: 'ownership',
          portfolioId: 'income',
          assignedAt: DateTime.utc(2026, 6, 30),
        ),
      ],
      range: PortfolioTrendRange.month,
      now: end,
    );

    final series = result['income']!;
    expect(series.points, hasLength(greaterThan(2)));
    expect(series.currentValue, _d('1100'));
    expect(series.periodNetFlow, Decimal.zero);
    expect(series.periodPerformanceRatio, closeTo(0.1, 0.000001));
  });

  test('treats newly included capital as flow instead of return', () async {
    const service = PortfolioTrendService(
      holdings: _SampledHoldings(),
      converter: converter,
      baseCurrency: 'USD',
    );

    final result = await service.computeMany(
      portfolios: [_portfolio('income')],
      assignmentHistory: [
        _assignment(
          id: 'ownership',
          portfolioId: 'income',
          assignedAt: DateTime.utc(2026, 7, 15),
        ),
      ],
      range: PortfolioTrendRange.month,
      now: end,
    );

    final series = result['income']!;
    expect(series.currentValue, _d('1000'));
    expect(series.periodNetFlow, _d('1000'));
    expect(series.periodPerformanceRatio, closeTo(0, 0.000001));
  });

  test('portfolio transfer keeps each side history stable', () async {
    const service = PortfolioTrendService(
      holdings: _SampledHoldings(growsOnLastDay: true),
      converter: converter,
      baseCurrency: 'USD',
    );
    final transferredAt = DateTime.utc(2026, 7, 15);

    final result = await service.computeMany(
      portfolios: [_portfolio('source'), _portfolio('destination')],
      assignmentHistory: [
        _assignment(
          id: 'source-period',
          portfolioId: 'source',
          assignedAt: DateTime.utc(2026, 6, 30),
          unassignedAt: transferredAt,
        ),
        _assignment(
          id: 'destination-period',
          portfolioId: 'destination',
          assignedAt: transferredAt,
        ),
      ],
      range: PortfolioTrendRange.month,
      now: end,
    );

    final source = result['source']!;
    final destination = result['destination']!;
    expect(
      source.points.any((point) => point.marketValueInBase > Decimal.zero),
      isTrue,
    );
    expect(source.currentValue, Decimal.zero);
    expect(source.periodNetFlow, _d('-1000'));
    expect(destination.currentValue, _d('1100'));
    expect(destination.periodNetFlow, _d('1000'));
    expect(destination.periodPerformanceRatio, closeTo(0.1, 0.000001));
  });
}
