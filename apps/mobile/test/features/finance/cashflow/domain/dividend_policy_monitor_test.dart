import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_event.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_policy_monitor.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

void main() {
  const monitor = DividendPolicyMonitor();
  final now = DateTime.utc(2026, 7, 1);

  test('flags critical drop when TTM is zero after non-zero prior TTM', () {
    final events = [
      _div(
        assetId: 'us:AAPL',
        label: 'AAPL',
        date: DateTime.utc(2024, 10, 1),
        gross: '100',
      ),
      _div(
        assetId: 'us:AAPL',
        label: 'AAPL',
        date: DateTime.utc(2025, 1, 15),
        gross: '100',
      ),
      // No dividends in TTM window [2025-07-01, 2026-07-01].
    ];

    final rows = monitor.detect(
      events: events,
      now: now,
      heldAssetIds: {'us:AAPL'},
    );

    expect(rows, hasLength(1));
    expect(rows.single.assetId, 'us:AAPL');
    expect(rows.single.severity, DividendDeteriorationSeverity.critical);
    expect(rows.single.dropRatio, 1.0);
    expect(rows.single.ttmGrossInBase, Decimal.zero);
    expect(rows.single.priorTtmGrossInBase, Decimal.fromInt(200));
  });

  test('flags warning when TTM falls between 20% and 50%', () {
    final events = [
      // Prior TTM [2024-07-01, 2025-07-01): 100
      _div(
        assetId: 'cn:600900',
        label: 'Yangtze Power',
        date: DateTime.utc(2024, 9, 1),
        gross: '100',
      ),
      // Current TTM [2025-07-01, 2026-07-01]: 75 → 25% drop
      _div(
        assetId: 'cn:600900',
        label: 'Yangtze Power',
        date: DateTime.utc(2025, 9, 1),
        gross: '75',
      ),
    ];

    final rows = monitor.detect(
      events: events,
      now: now,
      heldAssetIds: {'cn:600900'},
    );

    expect(rows, hasLength(1));
    expect(rows.single.severity, DividendDeteriorationSeverity.warning);
    expect(rows.single.dropRatio, closeTo(0.25, 1e-9));
  });

  test('returns empty when drop is under the warning threshold', () {
    final events = [
      _div(
        assetId: 'us:VOO',
        label: 'VOO',
        date: DateTime.utc(2024, 9, 1),
        gross: '100',
      ),
      _div(
        assetId: 'us:VOO',
        label: 'VOO',
        date: DateTime.utc(2025, 9, 1),
        gross: '95',
      ),
    ];

    expect(
      monitor.detect(events: events, now: now, heldAssetIds: {'us:VOO'}),
      isEmpty,
    );
  });

  test('ignores assets not currently held', () {
    final events = [
      _div(
        assetId: 'us:AAPL',
        label: 'AAPL',
        date: DateTime.utc(2024, 9, 1),
        gross: '100',
      ),
    ];

    expect(
      monitor.detect(events: events, now: now, heldAssetIds: {'us:MSFT'}),
      isEmpty,
    );
  });

  test('ignores unattributed dividend rows', () {
    final events = [
      _div(
        assetId: 'unattributed',
        label: '—',
        date: DateTime.utc(2024, 9, 1),
        gross: '100',
      ),
    ];

    expect(monitor.detect(events: events, now: now), isEmpty);
  });
}

DividendCenterEvent _div({
  required String assetId,
  required String label,
  required DateTime date,
  required String gross,
}) {
  final amount = Decimal.parse(gross);
  return DividendCenterEvent(
    event: CashFlowEvent(
      journalEntryId: '$assetId-$date',
      date: date,
      kind: CashFlowKind.dividend,
      signedAmount: amount,
      originalAmount: amount,
      currency: 'USD',
      accountId: 'cash',
      counterAccountSide: AccountSide.income,
    ),
    assetId: assetId,
    assetLabel: label,
    withholdingInBase: Decimal.zero,
    withholdingOriginal: Decimal.zero,
    withholdingCurrency: 'USD',
  );
}
