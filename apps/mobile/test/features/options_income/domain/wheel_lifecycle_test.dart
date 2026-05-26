import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/options_income/domain/options_strategy_profile.dart';
import 'package:naviwealth/features/options_income/domain/trade_journal_entry.dart';
import 'package:naviwealth/features/options_income/domain/wheel_lifecycle.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 5, 24),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
);

TradeJournalEntry _entry({
  String id = 'e',
  required OptionsStrategyKind strategy,
  required TradeJournalStatus status,
  String symbol = 'TSM',
  String currency = 'USD',
  DateTime? openedAt,
  DateTime? closedAt,
  String entryCredit = '0',
  String? exitDebit,
  String? realizedPnl,
}) => TradeJournalEntry(
  id: id,
  strategy: strategy,
  symbol: symbol,
  optionSymbol: '$symbol-OPT',
  openedAt: openedAt ?? DateTime.utc(2026, 5, 1),
  closedAt: closedAt,
  entryCredit: Decimal.parse(entryCredit),
  exitDebit: exitDebit == null ? null : Decimal.parse(exitDebit),
  realizedPnl: realizedPnl == null ? null : Decimal.parse(realizedPnl),
  currency: currency,
  status: status,
  notes: null,
  sync: _meta(),
);

void main() {
  group('buildWheelLifecycle stage derivation', () {
    test('empty entries yields a `between` stage with zero income', () {
      final cycle = buildWheelLifecycle(
        symbol: 'TSM',
        currency: 'USD',
        entries: const [],
      );
      expect(cycle.stage, WheelStage.between);
      expect(cycle.openPosition, isNull);
      expect(cycle.cumulativeIncome, Decimal.zero);
      expect(cycle.entries, isEmpty);
      expect(cycle.holdsShares, isFalse);
    });

    test('open cashSecuredPut pins stage to shortPut', () {
      final cycle = buildWheelLifecycle(
        symbol: 'TSM',
        currency: 'USD',
        entries: [
          _entry(
            id: 'open-put',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.open,
            entryCredit: '120',
          ),
        ],
      );
      expect(cycle.stage, WheelStage.shortPut);
      expect(cycle.openPosition?.id, 'open-put');
      // Open positions don't add to realised income yet.
      expect(cycle.cumulativeIncome, Decimal.zero);
    });

    test('expired put with no follow-up returns to cashWaiting', () {
      final cycle = buildWheelLifecycle(
        symbol: 'TSM',
        currency: 'USD',
        entries: [
          _entry(
            id: 'put-1',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.expired,
            entryCredit: '120',
            exitDebit: '0',
          ),
        ],
      );
      expect(cycle.stage, WheelStage.cashWaiting);
      expect(cycle.cumulativeIncome, Decimal.parse('120'));
      expect(cycle.holdsShares, isFalse);
    });

    test('assigned put leaves the lifecycle holding shares', () {
      final cycle = buildWheelLifecycle(
        symbol: 'TSM',
        currency: 'USD',
        entries: [
          _entry(
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.assigned,
            entryCredit: '120',
            exitDebit: '0',
          ),
        ],
      );
      expect(cycle.stage, WheelStage.putAssigned);
      expect(cycle.holdsShares, isTrue);
    });

    test('open coveredCall while holding shares pins shortCall', () {
      final cycle = buildWheelLifecycle(
        symbol: 'TSM',
        currency: 'USD',
        entries: [
          _entry(
            id: 'put-1',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.assigned,
            openedAt: DateTime.utc(2026, 5, 1),
            entryCredit: '120',
            exitDebit: '0',
          ),
          _entry(
            id: 'call-1',
            strategy: OptionsStrategyKind.coveredCall,
            status: TradeJournalStatus.open,
            openedAt: DateTime.utc(2026, 5, 15),
            entryCredit: '80',
          ),
        ],
      );
      expect(cycle.stage, WheelStage.shortCall);
      expect(cycle.openPosition?.id, 'call-1');
      // Closed put contributes; open call does not yet.
      expect(cycle.cumulativeIncome, Decimal.parse('120'));
    });

    test('covered call expired keeps shares, accumulates income', () {
      final cycle = buildWheelLifecycle(
        symbol: 'TSM',
        currency: 'USD',
        entries: [
          _entry(
            id: 'put-1',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.assigned,
            openedAt: DateTime.utc(2026, 5, 1),
            entryCredit: '120',
            exitDebit: '0',
          ),
          _entry(
            id: 'call-1',
            strategy: OptionsStrategyKind.coveredCall,
            status: TradeJournalStatus.expired,
            openedAt: DateTime.utc(2026, 5, 15),
            entryCredit: '80',
            exitDebit: '0',
          ),
        ],
      );
      expect(cycle.stage, WheelStage.sharesHeld);
      expect(cycle.holdsShares, isTrue);
      expect(cycle.cumulativeIncome, Decimal.parse('200'));
    });

    test('called-away covered call rotates back to cashWaiting', () {
      final cycle = buildWheelLifecycle(
        symbol: 'TSM',
        currency: 'USD',
        entries: [
          _entry(
            id: 'put-1',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.assigned,
            openedAt: DateTime.utc(2026, 5, 1),
            entryCredit: '120',
            exitDebit: '0',
          ),
          _entry(
            id: 'call-1',
            strategy: OptionsStrategyKind.coveredCall,
            status: TradeJournalStatus.assigned,
            openedAt: DateTime.utc(2026, 5, 15),
            entryCredit: '80',
            exitDebit: '0',
          ),
        ],
      );
      expect(cycle.stage, WheelStage.cashWaiting);
      expect(cycle.holdsShares, isFalse);
      expect(cycle.cumulativeIncome, Decimal.parse('200'));
    });

    test('explicit realizedPnl overrides credit-minus-debit', () {
      final cycle = buildWheelLifecycle(
        symbol: 'TSM',
        currency: 'USD',
        entries: [
          _entry(
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.closed,
            entryCredit: '120',
            exitDebit: '50',
            realizedPnl: '60', // user adjusted for commissions
          ),
        ],
      );
      expect(cycle.cumulativeIncome, Decimal.parse('60'));
    });

    test('foreign-symbol entries are ignored', () {
      final cycle = buildWheelLifecycle(
        symbol: 'TSM',
        currency: 'USD',
        entries: [
          _entry(
            id: 'tsm-put',
            symbol: 'TSM',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.open,
          ),
          _entry(
            id: 'aapl-put',
            symbol: 'AAPL',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.assigned,
            entryCredit: '999',
          ),
        ],
      );
      expect(cycle.stage, WheelStage.shortPut);
      expect(cycle.entries.map((e) => e.id), ['tsm-put']);
      expect(cycle.cumulativeIncome, Decimal.zero);
    });

    test('open entry wins over a more recently closed entry', () {
      // Even though the assignment closes more recently in calendar time,
      // an open position is the authoritative current stage.
      final cycle = buildWheelLifecycle(
        symbol: 'TSM',
        currency: 'USD',
        entries: [
          _entry(
            id: 'open-call',
            strategy: OptionsStrategyKind.coveredCall,
            status: TradeJournalStatus.open,
            openedAt: DateTime.utc(2026, 5, 10),
          ),
          _entry(
            id: 'old-put',
            strategy: OptionsStrategyKind.cashSecuredPut,
            status: TradeJournalStatus.assigned,
            openedAt: DateTime.utc(2026, 5, 1),
            closedAt: DateTime.utc(2026, 5, 12),
          ),
        ],
      );
      expect(cycle.stage, WheelStage.shortCall);
      expect(cycle.openPosition?.id, 'open-call');
    });
  });
}
