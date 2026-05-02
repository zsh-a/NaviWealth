import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/invariants.dart';
import 'package:naviwealth/data/domain/journal_entry.dart';
import 'package:naviwealth/data/domain/posting.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/data/repositories/journal_entry_repository.dart';

/// Minimal `Map`-backed FX source for cross-currency builder tests. The
/// keys are `'<from>:<to>'`. Identity returns 1.
class _MapFxRateSource implements FxRateSource {
  _MapFxRateSource(this._rates);
  final Map<String, Decimal> _rates;

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) {
    if (from == to) return Decimal.one;
    return _rates['$from:$to'];
  }
}

SyncMeta _stamp() => SyncMeta(
  ownerUserId: 'u-test',
  updatedAt: DateTime.utc(2026),
  updatedByDevice: 'dev-test',
  hlc: const Hlc(wallMillis: 1700000000000, counter: 0, nodeId: 'dev-test'),
);

JournalEntry _materialiseEntry(JournalEntryDraft draft) {
  return JournalEntry(
    id: draft.id ?? 'je-test',
    date: draft.date,
    settledOn: draft.settledOn,
    narration: draft.narration,
    payee: draft.payee,
    tagIds: draft.tagIds,
    flag: draft.flag,
    sync: _stamp(),
  );
}

List<Posting> _materialisePostings(
  JournalEntryDraft entry,
  List<PostingDraft> drafts,
) {
  final je = _materialiseEntry(entry);
  return [
    for (var i = 0; i < drafts.length; i++)
      Posting(
        id: 'p-$i',
        journalEntryId: je.id,
        position: drafts[i].position ?? i,
        accountId: drafts[i].accountId,
        units: drafts[i].units,
        unit: drafts[i].unit,
        cost: drafts[i].cost,
        price: drafts[i].price,
        sync: je.sync,
      ),
  ];
}

JournalEntryBalanceReport _checkBalance(
  JournalEntryBuild build, {
  FxRateSource? fx,
  String baseCurrency = 'USD',
}) {
  final entry = _materialiseEntry(build.entry);
  final postings = _materialisePostings(build.entry, build.postings);
  return evaluateEntryBalance(
    entry: entry,
    postings: postings,
    fx: fx ?? const IdentityFxRateSource(),
    baseCurrency: baseCurrency,
  );
}

void main() {
  group('JournalEntryBuilders.buy', () {
    test('balances and shapes legs in the canonical order', () {
      final build = JournalEntryBuilders.buy(
        date: DateTime.utc(2026, 1, 15),
        accountId: 'a-brokerage',
        cashAccountId: 'a-cash',
        assetUnit: 'NASDAQ:AAPL',
        qty: Decimal.parse('100'),
        price: Decimal.parse('150.00'),
        quoteCurrency: 'USD',
        feeAmount: Decimal.parse('5.00'),
        feeAccountId: 'a-fee',
        taxAmount: Decimal.parse('2.50'),
        taxAccountId: 'a-tax',
      );

      final report = _checkBalance(build);
      expect(
        report.isBalanced,
        isTrue,
        reason: 'Σ(weight) = ${report.totalBaseWeight}',
      );

      // Three asset/expense debits + one cash credit, in the documented
      // order: asset, fee, tax, cash.
      expect(build.postings, hasLength(4));
      expect(build.postings[0].accountId, 'a-brokerage');
      expect(build.postings[0].unit, 'NASDAQ:AAPL');
      expect(build.postings[0].units, Decimal.parse('100'));
      expect(build.postings[0].cost, isNotNull);
      expect(build.postings[0].cost!.perUnit, Decimal.parse('150.00'));

      expect(build.postings[1].accountId, 'a-fee');
      expect(build.postings[1].units, Decimal.parse('5.00'));
      expect(build.postings[2].accountId, 'a-tax');
      expect(build.postings[2].units, Decimal.parse('2.50'));

      // 100*150 + 5 + 2.5 = 15007.5 USD out of the cash account.
      expect(build.postings[3].accountId, 'a-cash');
      expect(build.postings[3].units, Decimal.parse('-15007.5'));
      expect(build.postings[3].unit, 'USD');

      // Asset gets tagged onto the JE for analytics rollups.
      expect(build.entry.tagIds, contains('asset:NASDAQ:AAPL'));
    });

    test('balances without fee/tax legs', () {
      final build = JournalEntryBuilders.buy(
        date: DateTime.utc(2026, 1, 15),
        accountId: 'a-brokerage',
        cashAccountId: 'a-cash',
        assetUnit: 'NASDAQ:AAPL',
        qty: Decimal.parse('10'),
        price: Decimal.parse('100'),
        quoteCurrency: 'USD',
      );
      expect(_checkBalance(build).isBalanced, isTrue);
      expect(build.postings, hasLength(2));
    });

    test('foreign-currency fee adds an extra cash leg in that ccy', () {
      final build = JournalEntryBuilders.buy(
        date: DateTime.utc(2026, 1, 15),
        accountId: 'a-brokerage',
        cashAccountId: 'a-cash',
        assetUnit: 'NASDAQ:AAPL',
        qty: Decimal.parse('10'),
        price: Decimal.parse('100'),
        quoteCurrency: 'USD',
        feeAmount: Decimal.parse('40'),
        feeAccountId: 'a-fee',
        feeCurrency: 'CNY',
      );
      // Asset, fee (CNY), cash (USD), cash (CNY).
      expect(build.postings, hasLength(4));
      expect(build.postings[1].unit, 'CNY');
      expect(build.postings[2].unit, 'USD');
      expect(build.postings[2].units, Decimal.parse('-1000'));
      expect(build.postings[3].unit, 'CNY');
      expect(build.postings[3].units, Decimal.parse('-40'));

      // Σ folded to USD with rate 1 USD = 7 CNY (so 1 CNY = 1/7 USD).
      final fx = _MapFxRateSource({
        'CNY:USD': (Decimal.one / Decimal.parse('7')).toDecimal(scaleOnInfinitePrecision: 12),
      });
      final report = _checkBalance(build, fx: fx);
      expect(
        report.isBalanced,
        isTrue,
        reason: 'totalBaseWeight=${report.totalBaseWeight}',
      );
    });

    test('rejects negative quantity', () {
      expect(
        () => JournalEntryBuilders.buy(
          date: DateTime.utc(2026),
          accountId: 'a',
          cashAccountId: 'c',
          assetUnit: 'X',
          qty: Decimal.parse('-1'),
          price: Decimal.parse('1'),
          quoteCurrency: 'USD',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects fee amount without account', () {
      expect(
        () => JournalEntryBuilders.buy(
          date: DateTime.utc(2026),
          accountId: 'a',
          cashAccountId: 'c',
          assetUnit: 'X',
          qty: Decimal.one,
          price: Decimal.one,
          quoteCurrency: 'USD',
          feeAmount: Decimal.parse('1'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('JournalEntryBuilders.sell', () {
    test('emits closing leg + capital gains + cash leg', () {
      final build = JournalEntryBuilders.sell(
        date: DateTime.utc(2026, 6, 1),
        accountId: 'a-brokerage',
        cashAccountId: 'a-cash',
        capitalGainsAccountId: 'a-cap-gains',
        assetUnit: 'NASDAQ:AAPL',
        qty: Decimal.parse('50'),
        price: Decimal.parse('160.00'),
        quoteCurrency: 'USD',
        costPerUnit: Decimal.parse('150.00'),
        costCurrency: 'USD',
        lotId: 'lot-2026-01',
        acquiredOn: DateTime.utc(2026, 1, 15),
      );

      expect(_checkBalance(build).isBalanced, isTrue);

      // Asset close → cap-gains → cash.
      expect(build.postings, hasLength(3));
      expect(build.postings[0].accountId, 'a-brokerage');
      expect(build.postings[0].units, Decimal.parse('-50'));
      expect(build.postings[0].cost!.lotId, 'lot-2026-01');
      expect(build.postings[0].price!.perUnit, Decimal.parse('160.00'));

      // (160-150) * 50 = 500 realised gain, credited to income (-).
      expect(build.postings[1].accountId, 'a-cap-gains');
      expect(build.postings[1].units, Decimal.parse('-500.00'));

      // Net cash in = 50 * 160 = 8000 USD.
      expect(build.postings[2].accountId, 'a-cash');
      expect(build.postings[2].units, Decimal.parse('8000.00'));
    });

    test('fee subtracts from cash leg, not from realised PnL', () {
      final build = JournalEntryBuilders.sell(
        date: DateTime.utc(2026, 6, 1),
        accountId: 'a',
        cashAccountId: 'c',
        capitalGainsAccountId: 'cg',
        assetUnit: 'NASDAQ:AAPL',
        qty: Decimal.parse('50'),
        price: Decimal.parse('160'),
        quoteCurrency: 'USD',
        costPerUnit: Decimal.parse('150'),
        costCurrency: 'USD',
        feeAmount: Decimal.parse('5'),
        feeAccountId: 'a-fee',
      );
      expect(_checkBalance(build).isBalanced, isTrue);
      // CapitalGains stays at gross 500.
      final cg = build.postings.firstWhere((p) => p.accountId == 'cg');
      expect(cg.units, Decimal.parse('-500'));
      // Cash net is 8000 - 5 = 7995.
      final cash = build.postings.firstWhere((p) => p.accountId == 'c');
      expect(cash.units, Decimal.parse('7995'));
      // Fee leg lands at +5 (debit to expense).
      final fee = build.postings.firstWhere((p) => p.accountId == 'a-fee');
      expect(fee.units, Decimal.parse('5'));
    });

    test('cross-currency sell is rejected (FIR-132)', () {
      expect(
        () => JournalEntryBuilders.sell(
          date: DateTime.utc(2026),
          accountId: 'a',
          cashAccountId: 'c',
          capitalGainsAccountId: 'cg',
          assetUnit: 'X',
          qty: Decimal.one,
          price: Decimal.one,
          quoteCurrency: 'USD',
          costPerUnit: Decimal.one,
          costCurrency: 'CNY',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('JournalEntryBuilders.transfer', () {
    test('single-currency transfer is two equal-and-opposite legs', () {
      final build = JournalEntryBuilders.transfer(
        date: DateTime.utc(2026, 4, 1),
        fromAccountId: 'a-bank-a',
        toAccountId: 'a-bank-b',
        amount: Decimal.parse('1000'),
        currency: 'CNY',
      );
      expect(_checkBalance(build, baseCurrency: 'CNY').isBalanced, isTrue);
      expect(build.postings, hasLength(2));
      expect(build.postings[0].units, Decimal.parse('-1000'));
      expect(build.postings[1].units, Decimal.parse('1000'));
    });

    test('cross-currency transfer attaches a Price annotation pinning '
        'the user-chosen rate', () {
      final build = JournalEntryBuilders.transfer(
        date: DateTime.utc(2026, 4, 1),
        fromAccountId: 'a-usd',
        toAccountId: 'a-cny',
        amount: Decimal.parse('1000'),
        currency: 'USD',
        toAmount: Decimal.parse('7100'),
        toCurrency: 'CNY',
      );
      // Source leg is plain fiat; destination carries the price
      // annotation expressed as "1 CNY = 0.140... USD" — i.e.
      // amount / toAmount.
      expect(build.postings[0].price, isNull);
      final destPrice = build.postings[1].price;
      expect(destPrice, isNotNull);
      expect(destPrice!.currency, 'USD');
      // 1000 / 7100 = 0.140845070... — kept at 12 decimals to
      // preserve the user's rate without infinite-precision loss.
      expect(
        destPrice.perUnit,
        Decimal.parse('0.140845070422'),
      );
    });

    test('cross-currency transfer balances under identity FX because the '
        'price annotation overrides any source-table lookup', () {
      // Identity FX would otherwise crash on a non-trivial cross —
      // the price annotation makes the JE self-balancing without ever
      // calling fx.rate(USD, CNY, ...).
      final build = JournalEntryBuilders.transfer(
        date: DateTime.utc(2026, 4, 1),
        fromAccountId: 'a-usd',
        toAccountId: 'a-cny',
        amount: Decimal.parse('1000'),
        currency: 'USD',
        toAmount: Decimal.parse('7100'),
        toCurrency: 'CNY',
      );
      // Folded base = USD: source = -1000 USD; dest = 7100 CNY @
      // 0.140... USD/CNY = +1000 USD; sum = 0.
      final report = _checkBalance(build, baseCurrency: 'USD');
      expect(
        report.isBalanced,
        isTrue,
        reason: 'totalBaseWeight=${report.totalBaseWeight}',
      );
    });

    test('cross-currency transfer balances under any FxRateSource '
        '(price annotation wins over the lookup)', () {
      // A wildly-wrong FxRateSource shouldn't unbalance the JE — the
      // user said "I converted at this rate", and the price annotation
      // pins exactly that conversion. This is the elegant outcome of
      // moving from FX-source-driven balance to price-annotation-driven
      // balance.
      final build = JournalEntryBuilders.transfer(
        date: DateTime.utc(2026, 4, 1),
        fromAccountId: 'a-usd',
        toAccountId: 'a-cny',
        amount: Decimal.parse('1000'),
        currency: 'USD',
        toAmount: Decimal.parse('7100'),
        toCurrency: 'CNY',
      );
      final fx = _MapFxRateSource({
        // Deliberately wrong: claims 1 USD = 100 CNY.
        'USD:CNY': Decimal.parse('100'),
        'CNY:USD': Decimal.parse('0.01'),
      });
      final report = _checkBalance(build, fx: fx, baseCurrency: 'CNY');
      expect(
        report.isBalanced,
        isTrue,
        reason: 'totalBaseWeight=${report.totalBaseWeight}',
      );
    });

    test('same-currency transfer skips the price annotation', () {
      final build = JournalEntryBuilders.transfer(
        date: DateTime.utc(2026, 4, 1),
        fromAccountId: 'a',
        toAccountId: 'b',
        amount: Decimal.parse('1000'),
        currency: 'CNY',
      );
      expect(build.postings.every((p) => p.price == null), isTrue);
    });

    test('rejects zero amount', () {
      expect(
        () => JournalEntryBuilders.transfer(
          date: DateTime.utc(2026),
          fromAccountId: 'a',
          toAccountId: 'b',
          amount: Decimal.zero,
          currency: 'CNY',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('JournalEntryBuilders.expense', () {
    test('two-leg expense balances + tags pass through', () {
      final build = JournalEntryBuilders.expense(
        date: DateTime.utc(2026, 4, 15),
        expenseAccountId: 'a-food',
        fromAccountId: 'a-bank',
        amount: Decimal.parse('300'),
        currency: 'CNY',
        payee: 'Walmart',
        tagIds: const ['daily', 'family'],
      );
      expect(_checkBalance(build, baseCurrency: 'CNY').isBalanced, isTrue);
      expect(build.entry.payee, 'Walmart');
      expect(build.entry.tagIds, ['daily', 'family']);
      expect(build.postings.first.units, Decimal.parse('300'));
      expect(build.postings.last.units, Decimal.parse('-300'));
    });
  });

  group('JournalEntryBuilders.dividend', () {
    test('cash + income two-leg balances', () {
      final build = JournalEntryBuilders.dividend(
        date: DateTime.utc(2026, 3, 1),
        cashAccountId: 'a-cash',
        incomeAccountId: 'a-dividend',
        amount: Decimal.parse('200'),
        currency: 'USD',
        assetUnit: 'NASDAQ:AAPL',
      );
      expect(_checkBalance(build).isBalanced, isTrue);
      expect(build.postings, hasLength(2));
      expect(build.postings[0].units, Decimal.parse('200'));
      expect(build.postings[1].units, Decimal.parse('-200'));
      expect(build.entry.tagIds, contains('asset:NASDAQ:AAPL'));
    });

    test('withholding tax adds an expense leg, cash net of withholding', () {
      final build = JournalEntryBuilders.dividend(
        date: DateTime.utc(2026, 3, 1),
        cashAccountId: 'a-cash',
        incomeAccountId: 'a-dividend',
        amount: Decimal.parse('200'),
        currency: 'USD',
        withholdingAmount: Decimal.parse('30'),
        withholdingAccountId: 'a-tax',
      );
      expect(_checkBalance(build).isBalanced, isTrue);
      // Order: cash (170), income (-200), tax (30).
      expect(build.postings, hasLength(3));
      expect(build.postings[0].units, Decimal.parse('170'));
      expect(build.postings[1].units, Decimal.parse('-200'));
      expect(build.postings[2].units, Decimal.parse('30'));
    });
  });

  group('JournalEntryBuilders.liabilityPayment', () {
    test('three legs (principal, interest, cash) balance', () {
      final build = JournalEntryBuilders.liabilityPayment(
        date: DateTime.utc(2026, 5, 1),
        liabilityAccountId: 'a-mortgage',
        fromAccountId: 'a-bank',
        interestExpenseAccountId: 'a-interest',
        principal: Decimal.parse('500'),
        interest: Decimal.parse('50'),
        currency: 'CNY',
        amortizationEntryId: 'amort-1',
      );
      expect(_checkBalance(build, baseCurrency: 'CNY').isBalanced, isTrue);
      expect(build.postings, hasLength(3));
      // Liability: +principal (debit toward zero).
      expect(build.postings[0].accountId, 'a-mortgage');
      expect(build.postings[0].units, Decimal.parse('500'));
      // Interest expense leg.
      expect(build.postings[1].accountId, 'a-interest');
      expect(build.postings[1].units, Decimal.parse('50'));
      // Cash outflow.
      expect(build.postings[2].accountId, 'a-bank');
      expect(build.postings[2].units, Decimal.parse('-550'));
      expect(build.entry.tagIds, contains('amort:amort-1'));
    });

    test('zero interest collapses to a two-leg payment', () {
      final build = JournalEntryBuilders.liabilityPayment(
        date: DateTime.utc(2026, 5, 1),
        liabilityAccountId: 'a-mortgage',
        fromAccountId: 'a-bank',
        interestExpenseAccountId: 'a-interest',
        principal: Decimal.parse('500'),
        interest: Decimal.zero,
        currency: 'CNY',
      );
      expect(_checkBalance(build, baseCurrency: 'CNY').isBalanced, isTrue);
      expect(build.postings, hasLength(2));
      expect(build.postings[0].units, Decimal.parse('500'));
      expect(build.postings[1].units, Decimal.parse('-500'));
    });

    test('rejects all-zero payment', () {
      expect(
        () => JournalEntryBuilders.liabilityPayment(
          date: DateTime.utc(2026),
          liabilityAccountId: 'a',
          fromAccountId: 'b',
          interestExpenseAccountId: 'c',
          principal: Decimal.zero,
          interest: Decimal.zero,
          currency: 'CNY',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('JournalEntryBuilders.split', () {
    test('bonus split self-balances in the asset unit', () {
      final build = JournalEntryBuilders.split(
        date: DateTime.utc(2026, 6, 1),
        accountId: 'a-brokerage',
        splitsEquityAccountId: 'a-equity-splits',
        assetUnit: 'NASDAQ:AAPL',
        quoteCurrency: 'USD',
        addedQuantity: Decimal.parse('100'),
        lotId: 'lot-split-2026-06',
      );
      expect(_checkBalance(build).isBalanced, isTrue);
      expect(build.postings[0].units, Decimal.parse('100'));
      expect(build.postings[1].units, Decimal.parse('-100'));
      expect(build.postings[0].cost!.perUnit, Decimal.zero);
    });

    test('reverse split (negative addedQuantity) also balances', () {
      final build = JournalEntryBuilders.split(
        date: DateTime.utc(2026, 6, 1),
        accountId: 'a-brokerage',
        splitsEquityAccountId: 'a-equity-splits',
        assetUnit: 'NASDAQ:AAPL',
        quoteCurrency: 'USD',
        addedQuantity: Decimal.parse('-50'),
      );
      expect(_checkBalance(build).isBalanced, isTrue);
      expect(build.postings[0].units, Decimal.parse('-50'));
      expect(build.postings[1].units, Decimal.parse('50'));
    });

    test('rejects zero quantity', () {
      expect(
        () => JournalEntryBuilders.split(
          date: DateTime.utc(2026),
          accountId: 'a',
          splitsEquityAccountId: 'b',
          assetUnit: 'X',
          quoteCurrency: 'USD',
          addedQuantity: Decimal.zero,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('JournalEntryBuilders.openingBalance', () {
    test('positive amount on asset offsets equity', () {
      final build = JournalEntryBuilders.openingBalance(
        date: DateTime.utc(2026, 1, 1),
        accountId: 'a-bank',
        openingBalanceAccountId: 'a-equity-opening',
        amount: Decimal.parse('10000'),
        currency: 'CNY',
      );
      expect(_checkBalance(build, baseCurrency: 'CNY').isBalanced, isTrue);
      expect(build.postings[0].units, Decimal.parse('10000'));
      expect(build.postings[1].units, Decimal.parse('-10000'));
    });

    test('negative amount records a starting liability balance', () {
      final build = JournalEntryBuilders.openingBalance(
        date: DateTime.utc(2026, 1, 1),
        accountId: 'a-mortgage',
        openingBalanceAccountId: 'a-equity-opening',
        amount: Decimal.parse('-50000'),
        currency: 'CNY',
      );
      expect(_checkBalance(build, baseCurrency: 'CNY').isBalanced, isTrue);
      expect(build.postings[0].units, Decimal.parse('-50000'));
      expect(build.postings[1].units, Decimal.parse('50000'));
    });

    test('rejects zero amount', () {
      expect(
        () => JournalEntryBuilders.openingBalance(
          date: DateTime.utc(2026),
          accountId: 'a',
          openingBalanceAccountId: 'b',
          amount: Decimal.zero,
          currency: 'CNY',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
