import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/expense/data/expense_anomaly_insight_provider.dart';

Expense _expense(String id, String amount, DateTime date) => Expense(
  id: id,
  categoryId: 'expense-account',
  amount: Decimal.parse(amount),
  currency: 'CNY',
  tradeDate: date,
  note: id,
  sync: SyncMeta(
    ownerUserId: 'user',
    updatedAt: date,
    updatedByDevice: 'device',
    hlc: Hlc.zero('device'),
  ),
);

void main() {
  test('includes current-month expense details ordered by contribution', () {
    final summary = summarizeExpenseAnomaly(
      expenses: <Expense>[
        _expense('small', '100', DateTime.utc(2026, 7, 2)),
        _expense('large', '300', DateTime.utc(2026, 7, 3)),
        _expense('june', '100', DateTime.utc(2026, 6, 3)),
        _expense('may', '100', DateTime.utc(2026, 5, 3)),
        _expense('april', '100', DateTime.utc(2026, 4, 3)),
      ],
      now: DateTime.utc(2026, 7, 10),
      converter: FxRateCurrencyConverter(InMemoryFxRateLookup(const [])),
      baseCurrency: 'CNY',
    );

    expect(summary, isNotNull);
    expect(summary!.currentMonthExpenses.map((expense) => expense.id), <String>[
      'large',
      'small',
    ]);
  });
}
