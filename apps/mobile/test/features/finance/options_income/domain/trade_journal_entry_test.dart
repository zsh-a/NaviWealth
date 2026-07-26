import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';

void main() {
  test('copyWith can explicitly clear nullable lifecycle fields', () {
    final entry = TradeJournalEntry(
      underlyingAssetId: 'nasdaq:AAPL',
      id: 'entry',
      strategy: OptionsStrategyKind.cashSecuredPut,
      symbol: 'VOO',
      optionSymbol: 'VOO-OPT',
      openedAt: DateTime.utc(2026, 7, 1),
      closedAt: DateTime.utc(2026, 7, 20),
      entryCredit: Decimal.fromInt(100),
      exitDebit: Decimal.fromInt(20),
      realizedPnl: Decimal.fromInt(80),
      currency: 'USD',
      status: TradeJournalStatus.closed,
      notes: 'closed',
      sync: SyncMeta(
        ownerUserId: 'u',
        updatedAt: DateTime.utc(2026, 7, 20),
        updatedByDevice: 'd',
        hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
      ),
    );

    final reopened = entry.copyWith(
      status: TradeJournalStatus.open,
      closedAt: null,
      exitDebit: null,
      realizedPnl: null,
      notes: null,
    );

    expect(reopened.closedAt, isNull);
    expect(reopened.exitDebit, isNull);
    expect(reopened.realizedPnl, isNull);
    expect(reopened.notes, isNull);
  });

  test('tracked net P&L includes quantity and total fees', () {
    final entry = TradeJournalEntry(
      underlyingAssetId: 'nasdaq:AAPL',
      id: 'entry',
      strategy: OptionsStrategyKind.cashSecuredPut,
      symbol: 'VOO',
      optionSymbol: 'VOO-OPT',
      openedAt: DateTime.utc(2026, 7, 1),
      expirationAt: DateTime.utc(2026, 8, 1),
      closedAt: DateTime.utc(2026, 7, 20),
      entryCredit: Decimal.fromInt(100),
      exitDebit: Decimal.fromInt(20),
      fees: Decimal.fromInt(5),
      realizedPnl: null,
      currency: 'USD',
      status: TradeJournalStatus.closed,
      notes: null,
      contractQuantity: 2,
      sync: SyncMeta(
        ownerUserId: 'u',
        updatedAt: DateTime.utc(2026, 7, 20),
        updatedByDevice: 'd',
        hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
      ),
    );

    expect(entry.grossEntryCredit, Decimal.fromInt(200));
    expect(entry.grossExitDebit, Decimal.fromInt(40));
    expect(entry.trackedNetPnl, Decimal.fromInt(155));
  });

  test('assigned option realizes retained premium after fees', () {
    final entry = TradeJournalEntry(
      underlyingAssetId: 'nasdaq:AAPL',
      id: 'entry',
      strategy: OptionsStrategyKind.coveredCall,
      symbol: 'VOO',
      optionSymbol: 'VOO-OPT',
      openedAt: DateTime.utc(2026, 7, 1),
      closedAt: DateTime.utc(2026, 7, 20),
      entryCredit: Decimal.fromInt(100),
      exitDebit: null,
      fees: Decimal.fromInt(5),
      realizedPnl: null,
      currency: 'USD',
      status: TradeJournalStatus.assigned,
      notes: null,
      contractQuantity: 2,
      sync: SyncMeta(
        ownerUserId: 'u',
        updatedAt: DateTime.utc(2026, 7, 20),
        updatedByDevice: 'd',
        hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
      ),
    );

    expect(entry.trackedNetPnl, Decimal.fromInt(195));
  });
}
