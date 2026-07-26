import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_trade_stats.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';

void main() {
  test('buildOptionsTradeStats summarizes conservative realized P&L', () {
    final opened = DateTime.utc(2026, 1, 1);
    final stats = buildOptionsTradeStats([
      _entry(
        id: 'closed-win',
        symbol: 'AAPL',
        strategy: OptionsStrategyKind.cashSecuredPut,
        openedAt: opened,
        closedAt: DateTime.utc(2026, 1, 11),
        entryCredit: '120',
        exitDebit: '40',
        status: TradeJournalStatus.closed,
      ),
      _entry(
        id: 'expired',
        symbol: 'AAPL',
        strategy: OptionsStrategyKind.coveredCall,
        openedAt: opened,
        closedAt: DateTime.utc(2026, 1, 22),
        entryCredit: '60',
        status: TradeJournalStatus.expired,
      ),
      _entry(
        id: 'assigned',
        symbol: 'TSLA',
        strategy: OptionsStrategyKind.cashSecuredPut,
        openedAt: opened,
        closedAt: DateTime.utc(2026, 1, 15),
        entryCredit: '200',
        status: TradeJournalStatus.assigned,
      ),
      _entry(
        id: 'open',
        symbol: 'TSLA',
        strategy: OptionsStrategyKind.coveredCall,
        openedAt: opened,
        entryCredit: '30',
        status: TradeJournalStatus.open,
      ),
      _entry(
        id: 'hkd',
        symbol: '0700',
        strategy: OptionsStrategyKind.coveredCall,
        openedAt: opened,
        closedAt: DateTime.utc(2026, 1, 8),
        entryCredit: '88',
        realizedPnl: '70',
        currency: 'HKD',
        status: TradeJournalStatus.closed,
      ),
    ]);

    expect(stats.totalEntries, 5);
    expect(stats.openEntries, 1);
    expect(stats.assignedEntries, 1);
    expect(stats.expiredEntries, 1);

    final usd = stats.byCurrency.singleWhere((s) => s.currency == 'USD');
    expect(usd.totalPremium, Decimal.parse('410'));
    expect(usd.trackedRealizedPnl, Decimal.parse('340'));
    expect(usd.trackedRealizedCount, 3);
    expect(usd.winningCount, 3);
    expect(usd.winRate, 1);
    expect(usd.averageHoldingDays, 15);

    final hkd = stats.byCurrency.singleWhere((s) => s.currency == 'HKD');
    expect(hkd.trackedRealizedPnl, Decimal.parse('70'));

    final aapl = stats.bySymbol.singleWhere((s) => s.symbol == 'AAPL');
    expect(aapl.entryCount, 2);
    expect(aapl.expiredCount, 1);
    expect(aapl.trackedRealizedPnlByCurrency['USD'], Decimal.parse('140'));

    final tsla = stats.bySymbol.singleWhere((s) => s.symbol == 'TSLA');
    expect(tsla.assignedCount, 1);
    expect(tsla.openCount, 1);
    expect(tsla.trackedRealizedPnlByCurrency['USD'], Decimal.parse('200'));
  });
}

TradeJournalEntry _entry({
  required String id,
  required String symbol,
  required OptionsStrategyKind strategy,
  required DateTime openedAt,
  DateTime? closedAt,
  required String entryCredit,
  String? exitDebit,
  String? realizedPnl,
  String currency = 'USD',
  required TradeJournalStatus status,
}) {
  return TradeJournalEntry(
    underlyingAssetId: 'nasdaq:AAPL',
    id: id,
    strategy: strategy,
    symbol: symbol,
    optionSymbol: '$symbol-option',
    openedAt: openedAt,
    closedAt: closedAt,
    entryCredit: Decimal.parse(entryCredit),
    exitDebit: exitDebit == null ? null : Decimal.parse(exitDebit),
    realizedPnl: realizedPnl == null ? null : Decimal.parse(realizedPnl),
    currency: currency,
    status: status,
    notes: null,
    sync: SyncMeta(
      ownerUserId: 'owner',
      updatedAt: DateTime.utc(2026),
      updatedByDevice: 'test',
      hlc: Hlc.zero('test'),
    ),
  );
}
