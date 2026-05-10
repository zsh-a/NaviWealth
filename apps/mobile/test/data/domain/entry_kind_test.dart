import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/entry_kind.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/posting.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';

const _hlc = Hlc(wallMillis: 1700000000000, counter: 0, nodeId: 'dev');
final _sync = SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'dev',
  hlc: _hlc,
);

Posting _p({
  required String accountId,
  required Decimal units,
  required String unit,
  Cost? cost,
  Price? price,
  int position = 0,
}) =>
    Posting(
      id: 'p-$accountId-$position',
      journalEntryId: 'je-1',
      position: position,
      accountId: accountId,
      units: units,
      unit: unit,
      cost: cost,
      price: price,
      sync: _sync,
    );

AccountSide? Function(String) _categoryMap(
  Map<String, AccountSide> m,
) =>
    (id) => m[id];

void main() {
  group('classifyEntryKind', () {
    test('empty postings → other', () {
      final result = classifyEntryKind(
        postings: const [],
        resolveCategory: (_) => null,
      );
      expect(result.kind, EntryKind.other);
      expect(result.isInflow, isNull);
    });

    test('unknown account → other (graceful when tree is hydrating)', () {
      final result = classifyEntryKind(
        postings: [
          _p(
            accountId: 'mystery',
            units: Decimal.parse('100'),
            unit: 'USD',
          ),
        ],
        resolveCategory: (_) => null,
      );
      expect(result.kind, EntryKind.other);
    });

    test('buy: asset commodity + cash on the same brokerage → trade (-out)', () {
      final result = classifyEntryKind(
        postings: [
          _p(
            accountId: 'a-brokerage',
            units: Decimal.parse('100'),
            unit: 'NASDAQ:AAPL',
            cost: Cost(perUnit: Decimal.parse('150'), currency: 'USD'),
          ),
          _p(
            accountId: 'a-brokerage',
            units: Decimal.parse('-15000'),
            unit: 'USD',
            position: 1,
          ),
        ],
        resolveCategory: _categoryMap({
          'a-brokerage': AccountSide.asset,
        }),
      );
      expect(result.kind, EntryKind.trade);
      expect(result.isInflow, isFalse);
    });

    test('sell: asset commodity (-) + cash (+) + capital gains → income wins', () {
      // The sell builder emits a leg on Income:CapitalGains, which —
      // by §1.1 priority — classifies the JE as `income` rather than
      // `trade`. The badge layer disambiguates via the income sub-account.
      final result = classifyEntryKind(
        postings: [
          _p(
            accountId: 'a-brokerage',
            units: Decimal.parse('-50'),
            unit: 'NASDAQ:AAPL',
            cost: Cost(perUnit: Decimal.parse('150'), currency: 'USD'),
          ),
          _p(
            accountId: 'a-cap-gains',
            units: Decimal.parse('-500'),
            unit: 'USD',
            position: 1,
          ),
          _p(
            accountId: 'a-brokerage',
            units: Decimal.parse('8000'),
            unit: 'USD',
            position: 2,
          ),
        ],
        resolveCategory: _categoryMap({
          'a-brokerage': AccountSide.asset,
          'a-cap-gains': AccountSide.income,
        }),
      );
      expect(result.kind, EntryKind.income);
      expect(result.isInflow, isTrue);
    });

    test('transfer: two distinct fiat asset accounts, no commodities', () {
      final result = classifyEntryKind(
        postings: [
          _p(
            accountId: 'a-bank-a',
            units: Decimal.parse('-1000'),
            unit: 'CNY',
          ),
          _p(
            accountId: 'a-bank-b',
            units: Decimal.parse('1000'),
            unit: 'CNY',
            position: 1,
          ),
        ],
        resolveCategory: _categoryMap({
          'a-bank-a': AccountSide.asset,
          'a-bank-b': AccountSide.asset,
        }),
      );
      expect(result.kind, EntryKind.transfer);
      expect(result.isInflow, isNull);
    });

    test('expense: expense account + asset cash', () {
      final result = classifyEntryKind(
        postings: [
          _p(
            accountId: 'a-food',
            units: Decimal.parse('300'),
            unit: 'CNY',
          ),
          _p(
            accountId: 'a-bank',
            units: Decimal.parse('-300'),
            unit: 'CNY',
            position: 1,
          ),
        ],
        resolveCategory: _categoryMap({
          'a-food': AccountSide.expense,
          'a-bank': AccountSide.asset,
        }),
      );
      expect(result.kind, EntryKind.expense);
      expect(result.isInflow, isFalse);
    });

    test('income: salary deposit', () {
      final result = classifyEntryKind(
        postings: [
          _p(
            accountId: 'a-bank',
            units: Decimal.parse('10000'),
            unit: 'CNY',
          ),
          _p(
            accountId: 'a-salary',
            units: Decimal.parse('-10000'),
            unit: 'CNY',
            position: 1,
          ),
        ],
        resolveCategory: _categoryMap({
          'a-bank': AccountSide.asset,
          'a-salary': AccountSide.income,
        }),
      );
      expect(result.kind, EntryKind.income);
      expect(result.isInflow, isTrue);
    });

    test('payment: liability + asset (+ optional interest expense)', () {
      final result = classifyEntryKind(
        postings: [
          _p(
            accountId: 'a-mortgage',
            units: Decimal.parse('500'),
            unit: 'CNY',
          ),
          _p(
            accountId: 'a-interest',
            units: Decimal.parse('50'),
            unit: 'CNY',
            position: 1,
          ),
          _p(
            accountId: 'a-bank',
            units: Decimal.parse('-550'),
            unit: 'CNY',
            position: 2,
          ),
        ],
        resolveCategory: _categoryMap({
          'a-mortgage': AccountSide.liability,
          'a-interest': AccountSide.expense,
          'a-bank': AccountSide.asset,
        }),
      );
      // Liability presence wins over the Expense interest leg.
      expect(result.kind, EntryKind.payment);
      expect(result.isInflow, isFalse);
    });

    test('adjustment: equity + asset commodity in same unit (split)', () {
      final result = classifyEntryKind(
        postings: [
          _p(
            accountId: 'a-brokerage',
            units: Decimal.parse('100'),
            unit: 'NASDAQ:AAPL',
            cost: Cost(perUnit: Decimal.zero, currency: 'USD'),
          ),
          _p(
            accountId: 'a-equity-splits',
            units: Decimal.parse('-100'),
            unit: 'NASDAQ:AAPL',
            cost: Cost(perUnit: Decimal.zero, currency: 'USD'),
            position: 1,
          ),
        ],
        resolveCategory: _categoryMap({
          'a-brokerage': AccountSide.asset,
          'a-equity-splits': AccountSide.equity,
        }),
      );
      expect(result.kind, EntryKind.adjustment);
      expect(result.isInflow, isNull); // pure unit-self-balance, no cash move
    });

    test('opening: equity + asset cash (no commodity legs)', () {
      final result = classifyEntryKind(
        postings: [
          _p(
            accountId: 'a-bank',
            units: Decimal.parse('10000'),
            unit: 'CNY',
          ),
          _p(
            accountId: 'a-equity-opening',
            units: Decimal.parse('-10000'),
            unit: 'CNY',
            position: 1,
          ),
        ],
        resolveCategory: _categoryMap({
          'a-bank': AccountSide.asset,
          'a-equity-opening': AccountSide.equity,
        }),
      );
      expect(result.kind, EntryKind.opening);
      expect(result.isInflow, isTrue);
    });

    test('liability opening seed (liability + equity) classifies as opening', () {
      // Beancount-style liability seed: pair a liability balance with
      // its Equity:OpeningBalance offset. No asset cash leg in this
      // shape, so isInflow stays absent — the badge simply renders the
      // generic "starting balance" affordance.
      final result = classifyEntryKind(
        postings: [
          _p(
            accountId: 'a-mortgage',
            units: Decimal.parse('-50000'),
            unit: 'CNY',
          ),
          _p(
            accountId: 'a-equity-opening',
            units: Decimal.parse('50000'),
            unit: 'CNY',
            position: 1,
          ),
        ],
        resolveCategory: _categoryMap({
          'a-mortgage': AccountSide.liability,
          'a-equity-opening': AccountSide.equity,
        }),
      );
      expect(result.kind, EntryKind.opening);
      // No asset legs touched ⇒ assetCashSum stays at zero ⇒ isInflow
      // is `false` under the strict `> 0` check. Pin the contract so a
      // future change to inflow semantics doesn't slip past review.
      expect(result.isInflow, isFalse);
    });
  });
}
