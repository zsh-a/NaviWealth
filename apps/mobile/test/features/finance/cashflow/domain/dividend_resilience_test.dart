import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_event.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_resilience.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';

void main() {
  const service = DividendResilienceService();

  test('builds rolling TTM, CAGR, concentration and coverage metrics', () {
    final events = <DividendCenterEvent>[];
    for (var month = 0; month < 36; month++) {
      final date = DateTime.utc(2023, 1 + month, 15);
      final gross = month < 24 ? 100 : 121;
      events.add(
        _event(
          id: 'a-$month',
          date: date,
          assetId: 'a',
          label: 'Alpha',
          grossOriginal: gross,
          netOriginal: gross * 9 ~/ 10,
          baseRate: 1,
        ),
      );
      events.add(
        _event(
          id: 'b-$month',
          date: date,
          assetId: 'b',
          label: 'Beta',
          grossOriginal: gross ~/ 3,
          netOriginal: gross * 3 ~/ 10,
          baseRate: 1,
        ),
      );
    }

    final report = service.analyze(
      events: events,
      now: DateTime.utc(2026, 1, 20),
    );

    expect(report.rolling.length, 25);
    expect(report.rolling.every((point) => point.hasFullWindow), isTrue);
    expect(report.netIncomeCagr, closeTo(math.sqrt(1.2) - 1, 0.001));
    expect(report.largestSourceLabel, 'Alpha');
    expect(report.largestSourceShare, closeTo(0.75, 0.01));
    expect(report.sourceConcentration, closeTo(0.625, 0.02));
    expect(report.observedMonthCount, 37);
    expect(report.recordedMonthCount, 36);
    expect(report.expectedPaymentCount, 72);
    expect(report.missingExpectedPaymentCount, 0);
    expect(report.confidence, DividendResilienceConfidence.medium);
  });

  test('finds maximum rolling-income drawdown and recovery time', () {
    final events = <DividendCenterEvent>[];
    for (var month = 0; month < 48; month++) {
      final gross = switch (month) {
        < 18 => 100,
        < 30 => 50,
        _ => 100,
      };
      events.add(
        _event(
          id: 'a-$month',
          date: DateTime.utc(2022, 1 + month, 15),
          assetId: 'a',
          label: 'Alpha',
          grossOriginal: gross,
          netOriginal: gross,
          baseRate: 1,
        ),
      );
    }

    final report = service.analyze(
      events: events,
      now: DateTime.utc(2026, 1, 20),
    );

    expect(report.maxDrawdown, isNotNull);
    expect(report.maxDrawdown!.ratio, closeTo(0.5, 0.001));
    expect(report.maxDrawdown!.recoveryMonths, 12);
  });

  test('separates holding, per-share and FX effects with matched evidence', () {
    final prior = _event(
      id: 'prior',
      date: DateTime.utc(2024, 6, 15),
      assetId: 'a',
      label: 'Alpha',
      grossOriginal: 100,
      netOriginal: 90,
      baseRate: 1,
    );
    final current = _event(
      id: 'current',
      date: DateTime.utc(2025, 6, 15),
      assetId: 'a',
      label: 'Alpha',
      grossOriginal: 240,
      netOriginal: 216,
      baseRate: 2,
    );
    final actions = [
      _action(id: 'prior', date: prior.event.date, dps: 1),
      _action(id: 'current', date: current.event.date, dps: 2),
    ];

    final report = service.analyze(
      events: [prior, current],
      now: DateTime.utc(2026, 1, 20),
      corporateActions: actions,
    );
    final row = report.attributions.single;

    expect(row.matchedUnitDividend, isTrue);
    expect(row.holdingQuantityImpact, Decimal.fromInt(20));
    expect(row.unitDividendImpact, Decimal.fromInt(120));
    expect(row.fxImpact, Decimal.fromInt(240));
    expect(row.totalChange, Decimal.fromInt(380));
    expect(row.primaryDriver, DividendChangeDriver.fx);
    expect(report.unitDividendMatchRatio, 1);
  });

  test(
    'keeps quantity and unit effects combined without per-share evidence',
    () {
      final report = service.analyze(
        events: [
          _event(
            id: 'prior',
            date: DateTime.utc(2024, 6, 15),
            assetId: 'a',
            label: 'Alpha',
            grossOriginal: 100,
            netOriginal: 90,
            baseRate: 1,
          ),
          _event(
            id: 'current',
            date: DateTime.utc(2025, 6, 15),
            assetId: 'a',
            label: 'Alpha',
            grossOriginal: 150,
            netOriginal: 135,
            baseRate: 1,
          ),
        ],
        now: DateTime.utc(2026, 1, 20),
        excludedEventCount: 1,
      );
      final row = report.attributions.single;

      expect(row.matchedUnitDividend, isFalse);
      expect(row.localCombinedImpact, Decimal.fromInt(50));
      expect(row.primaryDriver, DividendChangeDriver.localCombined);
      expect(report.confidence, DividendResilienceConfidence.low);
      expect(report.excludedEventCount, 1);
    },
  );

  test('reports high confidence only with long, attributable evidence', () {
    final events = <DividendCenterEvent>[];
    final actions = <CashDividendAction>[];
    for (var month = 0; month < 25; month++) {
      final id = 'a-$month';
      final date = DateTime.utc(2024, 1 + month, 15);
      events.add(
        _event(
          id: id,
          date: date,
          assetId: 'a',
          label: 'Alpha',
          grossOriginal: 100,
          netOriginal: 90,
          baseRate: 1,
        ),
      );
      actions.add(_action(id: id, date: date, dps: 1));
    }

    final report = service.analyze(
      events: events,
      now: DateTime.utc(2026, 2, 1),
      corporateActions: actions,
    );

    expect(report.unitDividendMatchRatio, 1);
    expect(report.confidence, DividendResilienceConfidence.high);
  });

  test('quarterly cadence does not treat normal empty months as missing', () {
    final events = <DividendCenterEvent>[];
    for (var quarter = 0; quarter < 8; quarter++) {
      events.add(
        _event(
          id: 'q-$quarter',
          date: DateTime.utc(2024, 1 + quarter * 3, 15),
          assetId: 'a',
          label: 'Alpha',
          grossOriginal: 100,
          netOriginal: 90,
          baseRate: 1,
        ),
      );
    }

    final report = service.analyze(
      events: events,
      now: DateTime.utc(2026, 1, 20),
    );

    expect(report.recordedMonthCount, 8);
    expect(report.expectedPaymentCount, 8);
    expect(report.missingExpectedPaymentCount, 0);
    expect(report.irregularAssetCount, 0);
  });

  test('quarterly cadence reports a genuinely missed payment', () {
    final events = <DividendCenterEvent>[];
    for (final month in [1, 4, 7, 10, 13, 19, 22]) {
      events.add(
        _event(
          id: 'q-$month',
          date: DateTime.utc(2024, month, 15),
          assetId: 'a',
          label: 'Alpha',
          grossOriginal: 100,
          netOriginal: 90,
          baseRate: 1,
        ),
      );
    }

    final report = service.analyze(
      events: events,
      now: DateTime.utc(2026, 1, 20),
    );

    expect(report.expectedPaymentCount, 8);
    expect(report.missingExpectedPaymentCount, 1);
    expect(report.irregularAssetCount, 0);
  });

  test('rejects currency-mismatched per-share evidence', () {
    final prior = _event(
      id: 'prior',
      date: DateTime.utc(2024, 6, 15),
      assetId: 'a',
      label: 'Alpha',
      grossOriginal: 100,
      netOriginal: 90,
      baseRate: 1,
    );
    final current = _event(
      id: 'current',
      date: DateTime.utc(2025, 6, 15),
      assetId: 'a',
      label: 'Alpha',
      grossOriginal: 150,
      netOriginal: 135,
      baseRate: 1,
    );

    final report = service.analyze(
      events: [prior, current],
      now: DateTime.utc(2026, 1, 20),
      corporateActions: [
        _action(id: 'prior', date: prior.event.date, dps: 1),
        _action(
          id: 'current',
          date: current.event.date,
          dps: 1,
          currency: 'EUR',
        ),
      ],
    );

    expect(report.attributions.single.matchedUnitDividend, isFalse);
    expect(
      report.attributions.single.primaryDriver,
      DividendChangeDriver.localCombined,
    );
    expect(report.unitDividendMatchRatio, 0.5);
  });

  test('rejects duplicate payout evidence for the same transaction', () {
    final prior = _event(
      id: 'prior',
      date: DateTime.utc(2024, 6, 15),
      assetId: 'a',
      label: 'Alpha',
      grossOriginal: 100,
      netOriginal: 90,
      baseRate: 1,
    );
    final current = _event(
      id: 'current',
      date: DateTime.utc(2025, 6, 15),
      assetId: 'a',
      label: 'Alpha',
      grossOriginal: 150,
      netOriginal: 135,
      baseRate: 1,
    );
    final duplicate = _action(id: 'current', date: current.event.date, dps: 1);

    final report = service.analyze(
      events: [prior, current],
      now: DateTime.utc(2026, 1, 20),
      corporateActions: [
        _action(id: 'prior', date: prior.event.date, dps: 1),
        duplicate,
        CashDividendAction(
          id: 'duplicate-row',
          assetId: duplicate.assetId,
          effectiveDate: duplicate.effectiveDate,
          transactionId: duplicate.transactionId,
          accountId: duplicate.accountId,
          currency: duplicate.currency,
          amountPerShare: duplicate.amountPerShare,
          withholdingTax: duplicate.withholdingTax,
        ),
      ],
    );

    expect(report.attributions.single.matchedUnitDividend, isFalse);
    expect(report.unitDividendMatchRatio, 0.5);
  });

  test('normalizes historical DPS for splits before attributing change', () {
    final prior = _event(
      id: 'prior',
      date: DateTime.utc(2024, 6, 15),
      assetId: 'a',
      label: 'Alpha',
      grossOriginal: 100,
      netOriginal: 90,
      baseRate: 1,
    );
    final current = _event(
      id: 'current',
      date: DateTime.utc(2025, 6, 15),
      assetId: 'a',
      label: 'Alpha',
      grossOriginal: 120,
      netOriginal: 108,
      baseRate: 1,
    );

    final report = service.analyze(
      events: [prior, current],
      now: DateTime.utc(2026, 1, 20),
      corporateActions: [
        _action(id: 'prior', date: prior.event.date, dps: 1),
        _actionWithDps(
          id: 'current',
          date: current.event.date,
          dps: Decimal.parse('0.5'),
        ),
        SplitAction(
          id: 'split',
          assetId: 'a',
          effectiveDate: DateTime.utc(2025, 1, 2),
          ratio: Decimal.fromInt(2),
        ),
      ],
    );
    final row = report.attributions.single;

    expect(row.matchedUnitDividend, isTrue);
    expect(row.unitDividendImpact.abs(), lessThan(Decimal.parse('0.0001')));
    expect(row.holdingQuantityImpact, Decimal.fromInt(20));
    expect(row.primaryDriver, DividendChangeDriver.holdingQuantity);
  });

  test('normalizes historical DPS for stock dividends', () {
    final prior = _event(
      id: 'prior',
      date: DateTime.utc(2024, 6, 15),
      assetId: 'a',
      label: 'Alpha',
      grossOriginal: 100,
      netOriginal: 90,
      baseRate: 1,
    );
    final current = _event(
      id: 'current',
      date: DateTime.utc(2025, 6, 15),
      assetId: 'a',
      label: 'Alpha',
      grossOriginal: 110,
      netOriginal: 99,
      baseRate: 1,
    );

    final report = service.analyze(
      events: [prior, current],
      now: DateTime.utc(2026, 1, 20),
      corporateActions: [
        _action(id: 'prior', date: prior.event.date, dps: 1),
        _actionWithDps(
          id: 'current',
          date: current.event.date,
          dps: Decimal.parse('0.9090909090909091'),
        ),
        StockDividendAction(
          id: 'stock-dividend',
          assetId: 'a',
          effectiveDate: DateTime.utc(2025, 1, 2),
          bonusRatio: Decimal.parse('0.1'),
        ),
      ],
    );
    final row = report.attributions.single;

    expect(row.matchedUnitDividend, isTrue);
    expect(row.unitDividendImpact.abs(), lessThan(Decimal.parse('0.0001')));
    expect(
      (row.holdingQuantityImpact - Decimal.fromInt(10)).abs(),
      lessThan(Decimal.parse('0.0001')),
    );
    expect(row.primaryDriver, DividendChangeDriver.holdingQuantity);
  });
}

DividendCenterEvent _event({
  required String id,
  required DateTime date,
  required String assetId,
  required String label,
  required int grossOriginal,
  required int netOriginal,
  required int baseRate,
}) {
  final net = Decimal.fromInt(netOriginal);
  final withholding = Decimal.fromInt(grossOriginal - netOriginal);
  return DividendCenterEvent(
    event: CashFlowEvent(
      journalEntryId: id,
      date: date,
      kind: CashFlowKind.dividend,
      signedAmount: net * Decimal.fromInt(baseRate),
      originalAmount: net,
      currency: 'USD',
      accountId: 'cash',
      counterAccountSide: AccountSide.income,
    ),
    assetId: assetId,
    assetLabel: label,
    withholdingInBase: withholding * Decimal.fromInt(baseRate),
    withholdingOriginal: withholding,
    withholdingCurrency: 'USD',
  );
}

CashDividendAction _action({
  required String id,
  required DateTime date,
  required int dps,
  String currency = 'USD',
}) => CashDividendAction(
  id: id,
  assetId: 'a',
  effectiveDate: date,
  transactionId: id,
  accountId: 'cash',
  currency: currency,
  amountPerShare: Decimal.fromInt(dps),
  withholdingTax: Decimal.zero,
);

CashDividendAction _actionWithDps({
  required String id,
  required DateTime date,
  required Decimal dps,
}) => CashDividendAction(
  id: id,
  assetId: 'a',
  effectiveDate: date,
  transactionId: id,
  accountId: 'cash',
  currency: 'USD',
  amountPerShare: dps,
  withholdingTax: Decimal.zero,
);
