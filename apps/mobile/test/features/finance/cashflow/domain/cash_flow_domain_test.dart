import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_aggregator.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_classifier.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_event.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_ledger_entry.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

void main() {
  group('CashFlow classifier', () {
    final accounts = {
      for (final account in [
        _account('cash', 'Checking', AccountSide.asset),
        _account('broker', 'Brokerage', AccountSide.asset),
        _account('salary', 'Salary', AccountSide.income),
        _account('dividend', 'Dividend', AccountSide.income),
        _account('interest', 'Interest', AccountSide.income),
        _account('capital', 'Capital Gains', AccountSide.income),
        _account('food', 'Food', AccountSide.expense),
        _account('opening', 'Opening Balance', AccountSide.equity),
      ])
        account.id: account,
    };

    CashFlowEvent? classify(CashFlowLedgerEntry entry) {
      return classifyCashFlowEvent(entry, resolveAccount: (id) => accounts[id]);
    }

    test('classifies income leaves by system account name', () {
      expect(
        classify(
          _entry('salary-je', [
            _post('cash', '1000'),
            _post('salary', '-1000'),
          ]),
        )!.kind,
        CashFlowKind.salary,
      );
      expect(
        classify(
          _entry('dividend-je', [
            _post('broker', '12.5'),
            _post('dividend', '-12.5'),
          ]),
        )!.kind,
        CashFlowKind.dividend,
      );
      expect(
        classify(
          _entry('interest-je', [_post('cash', '8'), _post('interest', '-8')]),
        )!.kind,
        CashFlowKind.interest,
      );
      expect(
        classify(
          _entry('capital-je', [
            _post('broker', '300'),
            _post('capital', '-300'),
          ]),
        )!.kind,
        CashFlowKind.capitalGains,
      );
    });

    test('classifies expense, transfer, and opening cash flows', () {
      final expense = classify(
        _entry('expense-je', [_post('cash', '-45'), _post('food', '45')]),
      )!;
      expect(expense.kind, CashFlowKind.expense);
      expect(expense.signedAmount, Decimal.parse('-45'));
      expect(expense.counterAccountSide, AccountSide.expense);

      final transfer = classify(
        _entry('transfer-je', [_post('cash', '-100'), _post('broker', '100')]),
      )!;
      expect(transfer.kind, CashFlowKind.transfer);
      expect(transfer.signedAmount, Decimal.parse('-100'));

      final opening = classify(
        _entry('opening-je', [
          _post('cash', '5000'),
          _post('opening', '-5000'),
        ]),
      )!;
      expect(opening.kind, CashFlowKind.opening);
      expect(opening.signedAmount, Decimal.parse('5000'));
    });
  });

  group('CashFlow aggregator', () {
    test('rolls up month buckets by kind and currency', () {
      final summary = aggregateCashFlow(
        [
          _event('salary-1', CashFlowKind.salary, '2026-01-10', '1000'),
          _event('salary-2', CashFlowKind.salary, '2026-01-20', '500'),
          _event('rent', CashFlowKind.expense, '2026-01-22', '-300'),
          _event('div', CashFlowKind.dividend, '2026-02-01', '12.5'),
        ],
        period: CashFlowPeriod.month,
        baseCurrency: 'USD',
      );

      expect(summary.totalInBase.amount, Decimal.parse('1212.5'));
      expect(summary.buckets.map((bucket) => bucket.key).toList(), [
        '2026-01',
        '2026-01',
        '2026-02',
      ]);
      final salary = summary.buckets.firstWhere(
        (bucket) => bucket.kind == CashFlowKind.salary,
      );
      expect(salary.totalInBase.amount, Decimal.parse('1500'));
      expect(salary.count, 2);
      final expense = summary.buckets.firstWhere(
        (bucket) => bucket.kind == CashFlowKind.expense,
      );
      expect(expense.totalInBase.amount, Decimal.parse('-300'));
    });

    test(
      'expense totals match expense module sign convention by magnitude',
      () {
        final summary = aggregateCashFlow(
          [
            _event('food', CashFlowKind.expense, '2026-03-03', '-120'),
            _event('rent', CashFlowKind.expense, '2026-03-04', '-1800'),
            _event('salary', CashFlowKind.salary, '2026-03-05', '5000'),
          ],
          period: CashFlowPeriod.month,
          baseCurrency: 'USD',
        );

        final expenseTotal = summary.buckets
            .where((bucket) => bucket.kind == CashFlowKind.expense)
            .fold<Decimal>(
              Decimal.zero,
              (sum, bucket) => sum + bucket.totalInBase.amount.abs(),
            );
        expect(expenseTotal, Decimal.parse('1920'));
      },
    );
  });
}

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 1, 1),
  updatedByDevice: 'd',
  hlc: Hlc.zero('d'),
);

Account _account(String id, String name, AccountSide side) => Account(
  id: id,
  type: AccountCategory.asset,
  name: name,
  currency: 'USD',
  category: side,
  sync: _meta(),
);

CashFlowLedgerEntry _entry(String id, List<CashFlowLedgerPosting> postings) {
  return CashFlowLedgerEntry(
    id: id,
    date: DateTime.utc(2026, 1, 10),
    postings: postings,
  );
}

CashFlowLedgerPosting _post(
  String accountId,
  String units, {
  String unit = 'USD',
}) => CashFlowLedgerPosting(
  accountId: accountId,
  units: Decimal.parse(units),
  unit: unit,
);

CashFlowEvent _event(String id, CashFlowKind kind, String date, String amount) {
  final value = Decimal.parse(amount);
  return CashFlowEvent(
    journalEntryId: id,
    date: DateTime.parse('${date}T00:00:00Z'),
    kind: kind,
    signedAmount: value,
    originalAmount: value,
    currency: 'USD',
    accountId: 'cash',
    counterAccountSide: kind == CashFlowKind.expense
        ? AccountSide.expense
        : AccountSide.income,
  );
}
