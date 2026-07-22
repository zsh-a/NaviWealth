import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';

void main() {
  test('copyWith can explicitly clear nullable lifecycle fields', () {
    final entry = TradeJournalEntry(
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
}
