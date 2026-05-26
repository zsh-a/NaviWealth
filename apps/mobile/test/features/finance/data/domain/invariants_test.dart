import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/hlc.dart';
import 'package:naviwealth/features/finance/data/domain/invariants.dart';
import 'package:naviwealth/features/finance/data/domain/journal_entry.dart';
import 'package:naviwealth/features/finance/data/domain/posting.dart';
import 'package:naviwealth/features/finance/data/domain/sync_meta.dart';

/// Deterministic [FxRateSource] backed by a fixed `(from, to) → rate`
/// map. Asks for an unknown pair return `null` so tests can exercise
/// the missing-rate problem path.
class _MapFx implements FxRateSource {
  _MapFx(this.rates);
  final Map<String, Decimal> rates;
  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) {
    if (from == to) return Decimal.one;
    return rates['$from/$to'];
  }
}

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u-test',
  updatedAt: DateTime.utc(2026, 1, 1),
  updatedByDevice: 'dev-test',
  hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'dev-test'),
);

JournalEntry _je({
  String id = 'je-1',
  EntryFlag flag = EntryFlag.confirmed,
  DateTime? date,
  String narration = 'Test',
}) => JournalEntry(
  id: id,
  date: date ?? DateTime.utc(2026, 1, 15),
  narration: narration,
  flag: flag,
  sync: _meta(),
);

Posting _p({
  String id = 'p',
  String accountId = 'acct',
  required String units,
  required String unit,
  Cost? cost,
  Price? price,
  int position = 0,
}) => Posting(
  id: id,
  journalEntryId: 'je-1',
  position: position,
  accountId: accountId,
  units: Decimal.parse(units),
  unit: unit,
  cost: cost,
  price: price,
  sync: _meta(),
);

void main() {
  // ---- 7 typical events from the spike body, all must balance. ----

  group('entryIsBalanced — 7 typical events', () {
    final fx = _MapFx({
      'USD/CNY': Decimal.parse('7.2'),
      'CNY/USD': Decimal.parse('0.1389'),
    });

    test('1. buy 100 AAPL with fee — 3 legs balance in USD', () {
      final je = _je(narration: 'Buy 100 AAPL');
      final postings = [
        _p(
          id: 'p1',
          accountId: 'acct:brokerage:hk',
          units: '100',
          unit: 'us_stock:AAPL',
          cost: Cost(perUnit: Decimal.parse('150.00'), currency: 'USD'),
          position: 0,
        ),
        _p(
          id: 'p2',
          accountId: 'acct:expense:trading_fee',
          units: '5.00',
          unit: 'USD',
          position: 1,
        ),
        _p(
          id: 'p3',
          accountId: 'acct:brokerage:cash',
          units: '-15005.00',
          unit: 'USD',
          position: 2,
        ),
      ];
      expect(
        entryIsBalanced(
          entry: je,
          postings: postings,
          fx: fx,
          baseCurrency: 'USD',
        ),
        isTrue,
      );
    });

    test('2. sell 50 AAPL with realized PnL — 3 legs balance', () {
      final je = _je(narration: 'Sell 50 AAPL');
      final postings = [
        _p(
          id: 'p1',
          units: '-50',
          unit: 'us_stock:AAPL',
          cost: Cost(perUnit: Decimal.parse('150.00'), currency: 'USD'),
          price: Price(perUnit: Decimal.parse('160.00'), currency: 'USD'),
        ),
        _p(
          id: 'p2',
          units: '-500.00',
          unit: 'USD',
          accountId: 'acct:income:capital_gains',
          position: 1,
        ),
        _p(
          id: 'p3',
          units: '8000.00',
          unit: 'USD',
          accountId: 'acct:brokerage:cash',
          position: 2,
        ),
      ];
      // weight(p1) uses cost: -50 × 150 = -7500
      // weight(p2)            = -500
      // weight(p3)            = 8000
      // total = 0
      final report = evaluateEntryBalance(
        entry: je,
        postings: postings,
        fx: fx,
        baseCurrency: 'USD',
      );
      expect(
        report.isBalanced,
        isTrue,
        reason: 'total=${report.totalBaseWeight}',
      );
    });

    test('3. AAPL Q1 dividend — 2 legs balance in USD', () {
      final je = _je(narration: 'AAPL Q1 Dividend');
      final postings = [
        _p(id: 'p1', units: '200.00', unit: 'USD', position: 0),
        _p(id: 'p2', units: '-200.00', unit: 'USD', position: 1),
      ];
      expect(
        entryIsBalanced(
          entry: je,
          postings: postings,
          fx: fx,
          baseCurrency: 'USD',
        ),
        isTrue,
      );
    });

    test('4. transfer Bank A → Bank B, single CNY currency', () {
      final je = _je(narration: 'Transfer A->B');
      final postings = [
        _p(id: 'p1', units: '-1000.00', unit: 'CNY', accountId: 'a'),
        _p(
          id: 'p2',
          units: '1000.00',
          unit: 'CNY',
          accountId: 'b',
          position: 1,
        ),
      ];
      expect(
        entryIsBalanced(
          entry: je,
          postings: postings,
          fx: fx,
          baseCurrency: 'CNY',
        ),
        isTrue,
      );
    });

    test('5. groceries (expense) — 2 legs balance', () {
      final je = _je(narration: 'Groceries', date: DateTime.utc(2026, 4, 15));
      final postings = [
        _p(
          id: 'p1',
          units: '300.00',
          unit: 'CNY',
          accountId: 'acct:expense:food',
        ),
        _p(
          id: 'p2',
          units: '-300.00',
          unit: 'CNY',
          accountId: 'acct:bank:a',
          position: 1,
        ),
      ];
      expect(
        entryIsBalanced(
          entry: je,
          postings: postings,
          fx: fx,
          baseCurrency: 'CNY',
        ),
        isTrue,
      );
    });

    test('6. mortgage payment — principal + interest + cash, 3 legs', () {
      final je = _je(narration: 'Mortgage Jan');
      final postings = [
        _p(
          id: 'p1',
          units: '500.00',
          unit: 'CNY',
          accountId: 'acct:liability:mortgage',
        ),
        _p(
          id: 'p2',
          units: '50.00',
          unit: 'CNY',
          accountId: 'acct:expense:interest',
          position: 1,
        ),
        _p(
          id: 'p3',
          units: '-550.00',
          unit: 'CNY',
          accountId: 'acct:bank:a',
          position: 2,
        ),
      ];
      expect(
        entryIsBalanced(
          entry: je,
          postings: postings,
          fx: fx,
          baseCurrency: 'CNY',
        ),
        isTrue,
      );
    });

    test('7. AAPL 2:1 split — unit-self-balance via Equity:Splits', () {
      // The split is currency-neutral (cost.perUnit = 0); the AAPL
      // dimension self-balances because the +100 lot and the -100 lot
      // weigh to zero in the cost currency.
      final je = _je(narration: 'AAPL 2:1 Split');
      final postings = [
        _p(
          id: 'p1',
          units: '100',
          unit: 'us_stock:AAPL',
          cost: Cost(perUnit: Decimal.zero, currency: 'USD'),
          accountId: 'acct:brokerage:hk',
        ),
        _p(
          id: 'p2',
          units: '-100',
          unit: 'us_stock:AAPL',
          cost: Cost(perUnit: Decimal.zero, currency: 'USD'),
          accountId: 'acct:equity:splits',
          position: 1,
        ),
      ];
      expect(
        entryIsBalanced(
          entry: je,
          postings: postings,
          fx: fx,
          baseCurrency: 'USD',
        ),
        isTrue,
      );
    });
  });

  // ---- 5 edge cases from the spike acceptance criteria. ----

  group('entryIsBalanced — edge cases', () {
    final fx = _MapFx({
      'USD/CNY': Decimal.parse('7.2'),
      'EUR/CNY': Decimal.parse('7.8'),
    });

    test('multi-currency JE balances when folded to base', () {
      // 100 USD * 7.2 - 720 CNY = 0 in base CNY.
      final je = _je(narration: 'Multi-currency exchange');
      final postings = [
        _p(id: 'p1', units: '-100.00', unit: 'USD', accountId: 'a'),
        _p(id: 'p2', units: '720.00', unit: 'CNY', accountId: 'b', position: 1),
      ];
      final report = evaluateEntryBalance(
        entry: je,
        postings: postings,
        fx: fx,
        baseCurrency: 'CNY',
      );
      expect(report.isBalanced, isTrue);
      expect(report.totalBaseWeight, Decimal.zero);
    });

    test('split-style unit self-balance ignores price coverage rule', () {
      // Two AAPL legs cancelling each other, with price annotation
      // (closing-leg case): cost wins for the weight, so total = 0.
      final je = _je();
      final postings = [
        _p(
          id: 'p1',
          units: '50',
          unit: 'us_stock:AAPL',
          cost: Cost(perUnit: Decimal.parse('100'), currency: 'USD'),
          price: Price(perUnit: Decimal.parse('110'), currency: 'USD'),
        ),
        _p(
          id: 'p2',
          units: '-50',
          unit: 'us_stock:AAPL',
          cost: Cost(perUnit: Decimal.parse('100'), currency: 'USD'),
          price: Price(perUnit: Decimal.parse('110'), currency: 'USD'),
          position: 1,
        ),
      ];
      expect(
        entryIsBalanced(
          entry: je,
          postings: postings,
          fx: fx,
          baseCurrency: 'USD',
        ),
        isTrue,
      );
    });

    test('cost annotation takes precedence over price for the weight', () {
      // Posting A weighs at cost (5 × 1 = 5), B at price (5 × 1 = 5).
      // If "price" had been chosen for A, A would weigh 5 × 100 = 500
      // and the JE would be massively unbalanced — this test pins the
      // tie-breaking rule.
      final je = _je();
      final postings = [
        _p(
          id: 'p1',
          units: '5',
          unit: 'us_stock:X',
          cost: Cost(perUnit: Decimal.one, currency: 'USD'),
          price: Price(perUnit: Decimal.parse('100'), currency: 'USD'),
        ),
        _p(id: 'p2', units: '-5.00', unit: 'USD', accountId: 'b', position: 1),
      ];
      expect(
        entryIsBalanced(
          entry: je,
          postings: postings,
          fx: fx,
          baseCurrency: 'USD',
        ),
        isTrue,
      );
    });

    test('tolerance: just inside passes, just outside fails', () {
      // A weight of 1 µ-cent (1e-6) is within the default tolerance.
      // 2 µ-cent is just outside.
      JournalEntryBalanceReport runWith(String off) => evaluateEntryBalance(
        entry: _je(),
        postings: [
          _p(id: 'p1', units: '1.00', unit: 'USD'),
          _p(
            id: 'p2',
            units: '-${Decimal.parse('1.00') - Decimal.parse(off)}',
            unit: 'USD',
            position: 1,
          ),
        ],
        fx: fx,
        baseCurrency: 'USD',
      );
      expect(runWith('0.000001').isBalanced, isTrue);
      expect(runWith('0.000002').isBalanced, isFalse);
    });

    test('empty postings list is reported as emptyEntry', () {
      final report = evaluateEntryBalance(
        entry: _je(),
        postings: const [],
        fx: fx,
        baseCurrency: 'USD',
      );
      expect(report.isBalanced, isFalse);
      expect(report.problems.single.kind, EntryBalanceProblemKind.emptyEntry);
    });

    test('non-fiat unit without cost or price is rejected', () {
      // A raw commodity leg with no annotation can't be folded.
      final je = _je();
      final report = evaluateEntryBalance(
        entry: je,
        postings: [
          _p(id: 'p1', units: '5', unit: 'us_stock:AAPL'),
          _p(id: 'p2', units: '-100', unit: 'USD', position: 1),
        ],
        fx: fx,
        baseCurrency: 'USD',
      );
      expect(report.isBalanced, isFalse);
      expect(
        report.problems.first.kind,
        EntryBalanceProblemKind.rawCommodityWithoutCostOrPrice,
      );
    });

    test('missing FX rate surfaces missingFxRate problem', () {
      final je = _je();
      final emptyFx = _MapFx(const {});
      final report = evaluateEntryBalance(
        entry: je,
        postings: [
          _p(id: 'p1', units: '-100', unit: 'EUR'),
          _p(id: 'p2', units: '120', unit: 'USD', position: 1),
        ],
        fx: emptyFx,
        baseCurrency: 'USD',
      );
      expect(report.isBalanced, isFalse);
      expect(
        report.problems.any(
          (p) => p.kind == EntryBalanceProblemKind.missingFxRate,
        ),
        isTrue,
      );
    });

    test('padding flag short-circuits the balance check', () {
      // Padding rows are explicitly exempt — they reconcile against an
      // externally-known total and aren't expected to balance on their
      // own.
      final je = _je(flag: EntryFlag.padding);
      expect(
        entryIsBalanced(
          entry: je,
          postings: [_p(id: 'p1', units: '999', unit: 'USD')],
          fx: fx,
          baseCurrency: 'USD',
        ),
        isTrue,
      );
    });
  });
}
