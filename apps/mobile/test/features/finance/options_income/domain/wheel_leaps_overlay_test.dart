import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/options_income/domain/leaps_call_position.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';
import 'package:naviwealth/features/finance/options_income/domain/wheel_leaps_overlay.dart';
import 'package:naviwealth/features/finance/options_income/domain/wheel_lifecycle.dart';

final _sync = SyncMeta(
  ownerUserId: 'user',
  updatedAt: DateTime.utc(2026, 7, 1),
  updatedByDevice: 'device',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'device'),
);

TradeJournalEntry _wheelEntry() => TradeJournalEntry(
  id: 'put',
  strategy: OptionsStrategyKind.cashSecuredPut,
  symbol: 'AAPL',
  optionSymbol: 'AAPL-P',
  openedAt: DateTime.utc(2026, 6, 1),
  closedAt: null,
  entryCredit: Decimal.parse('400'),
  exitDebit: null,
  fees: Decimal.parse('2'),
  realizedPnl: null,
  currency: 'USD',
  status: TradeJournalStatus.open,
  notes: null,
  sync: _sync,
);

LeapsCallPosition _leaps({
  String id = 'call',
  LeapsCallStatus status = LeapsCallStatus.open,
  String debit = '1200',
  String? exitCredit,
  String? delta = '0.7',
  String? mark = '1300',
  DateTime? expiration,
}) => LeapsCallPosition(
  id: id,
  symbol: 'AAPL',
  optionSymbol: 'AAPL-C',
  openedAt: DateTime.utc(2026, 1, 1),
  expirationAt: expiration ?? DateTime.utc(2028, 1, 1),
  closedAt: status == LeapsCallStatus.open ? null : DateTime.utc(2026, 7, 1),
  strikePrice: Decimal.parse('180'),
  entryDebit: Decimal.parse(debit),
  exitCredit: exitCredit == null ? null : Decimal.parse(exitCredit),
  fees: Decimal.parse('5'),
  currency: 'USD',
  contractSize: 100,
  contractQuantity: 1,
  status: status,
  currentMark: mark == null ? null : Decimal.parse(mark),
  currentDelta: delta == null ? null : Decimal.parse(delta),
  markedAt: DateTime.utc(2026, 7, 1),
  brokerageAccountId: null,
  notes: null,
  sync: _sync,
);

void main() {
  test('keeps LEAPS outside Wheel stage and exposes stacked risk', () {
    final wheel = buildWheelLifecycle(
      symbol: 'AAPL',
      currency: 'USD',
      entries: [_wheelEntry()],
    );
    final overlay = buildWheelLeapsOverlay(
      wheel: wheel,
      positions: [_leaps()],
      now: DateTime.utc(2026, 7, 1),
    );

    expect(overlay.wheel.stage, WheelStage.shortPut);
    expect(overlay.openLeapsCost, Decimal.parse('1205'));
    expect(overlay.deltaEquivalentShares, Decimal.parse('70.0'));
    expect(overlay.warnings, contains(WheelLeapsWarning.stackedDownside));
    expect(overlay.warnings, contains(WheelLeapsWarning.costNotCovered));
  });

  test('reports unknown exposure rather than inventing mark and delta', () {
    final overlay = buildWheelLeapsOverlay(
      wheel: WheelLifecycle.empty(symbol: 'AAPL', currency: 'USD'),
      positions: [_leaps(delta: null, mark: null)],
      now: DateTime.utc(2026, 7, 1),
    );

    expect(overlay.deltaEquivalentShares, isNull);
    expect(overlay.warnings, contains(WheelLeapsWarning.deltaUnavailable));
    expect(overlay.warnings, contains(WheelLeapsWarning.markUnavailable));
  });

  test('combines closed LEAPS P&L with realized Wheel income', () {
    final closedWheel = buildWheelLifecycle(
      symbol: 'AAPL',
      currency: 'USD',
      entries: [
        _wheelEntry().copyWith(
          status: TradeJournalStatus.expired,
          closedAt: DateTime.utc(2026, 6, 30),
        ),
      ],
    );
    final overlay = buildWheelLeapsOverlay(
      wheel: closedWheel,
      positions: [
        _leaps(
          status: LeapsCallStatus.closed,
          debit: '1200',
          exitCredit: '1500',
        ),
      ],
    );

    expect(overlay.realizedLeapsPnl, Decimal.parse('295'));
    expect(overlay.combinedRealizedPnl, Decimal.parse('693'));
  });

  test('treats an expired LEAPS debit and fees as a realized loss', () {
    final position = _leaps(
      status: LeapsCallStatus.expired,
      debit: '1200',
      mark: null,
      delta: null,
    );

    expect(position.realizedPnl, Decimal.parse('-1205'));
  });
}
