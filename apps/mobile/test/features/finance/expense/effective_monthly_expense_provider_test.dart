import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/expense/data/expense_report_providers.dart';
import 'package:naviwealth/features/finance/expense/domain/monthly_expense_derivation.dart';
import 'package:shared_preferences/shared_preferences.dart';

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 4, 1),
  updatedByDevice: 't',
  hlc: Hlc.zero('t'),
);

Expense _expense({
  required String id,
  required Decimal amount,
  required DateTime date,
}) => Expense(
  id: id,
  expenseAccountId: 'cat-1',
  amount: amount,
  currency: 'CNY',
  tradeDate: date,
  sync: _meta(),
);

Future<ProviderContainer> _container({
  List<Expense> expenses = const [],
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      journalExpensesStreamProvider.overrideWith(
        (ref) => Stream.value(expenses),
      ),
      // expense report converter chains through fxRatesStreamProvider →
      // appDatabaseProvider; stub it so tests don't touch the real DB.
      fxRatesStreamProvider.overrideWith(
        (ref) => Stream<List<FxRate>>.value(const []),
      ),
    ],
  );
}

void main() {
  test('falls back to auto-derivation when no override is set', () async {
    // Anchor the assertions around fixed historical months so the test
    // doesn't drift with the wall clock. The derivation excludes the
    // current month, so we use months that are guaranteed to be "complete"
    // — our provider hits the default 3-month window, but we only feed it
    // the last 3 months of data and verify it averages them.
    final today = DateTime.now();
    final firstOfThisMonth = DateTime.utc(today.year, today.month, 1);
    final firstOfLastMonth = _firstOfMonthBefore(firstOfThisMonth, 1);
    final firstOf3MonthsAgo = _firstOfMonthBefore(firstOfThisMonth, 3);

    final container = await _container(
      expenses: [
        _expense(
          id: 'm-3',
          amount: Decimal.parse('300'),
          date: firstOf3MonthsAgo.add(const Duration(days: 5)),
        ),
        _expense(
          id: 'm-1',
          amount: Decimal.parse('900'),
          date: firstOfLastMonth.add(const Duration(days: 5)),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Listen to keep the entire dependency chain alive.
    final sub = container.listen(effectiveMonthlyExpenseProvider, (p, n) {});
    addTearDown(sub.close);
    await container.read(journalExpensesStreamProvider.future);

    final effective = container
        .read(effectiveMonthlyExpenseProvider)
        .requireValue;
    expect(effective.source, MonthlyExpenseSource.auto);
    // (300 + 900) / 3 = 400
    expect(effective.value.amount, Decimal.parse('400'));
  });

  test('manual override short-circuits the rolling average', () async {
    final container = await _container(
      initialPrefs: const {
        'naviwealth.expense.monthly.override': '5000',
        'naviwealth.expense.monthly.window': 6,
      },
      expenses: const [],
    );
    addTearDown(container.dispose);
    final sub = container.listen(effectiveMonthlyExpenseProvider, (p, n) {});
    addTearDown(sub.close);
    await container.read(journalExpensesStreamProvider.future);

    final effective = container
        .read(effectiveMonthlyExpenseProvider)
        .requireValue;
    expect(effective.source, MonthlyExpenseSource.manual);
    expect(effective.value.amount, Decimal.parse('5000'));
    // The auto value is still carried alongside so the override UI can
    // render "auto would be …" beside the manual figure.
    expect(effective.auto.windowMonths, 6);
    expect(effective.auto.average.amount, Decimal.zero);
  });

  test('clearing the override returns to auto', () async {
    final container = await _container(
      initialPrefs: const {'naviwealth.expense.monthly.override': '999'},
      expenses: const [],
    );
    addTearDown(container.dispose);
    final sub = container.listen(effectiveMonthlyExpenseProvider, (p, n) {});
    addTearDown(sub.close);
    await container.read(journalExpensesStreamProvider.future);

    final controller = container.read(
      monthlyExpensePreferencesProvider.notifier,
    );
    expect(
      container.read(effectiveMonthlyExpenseProvider).requireValue.source,
      MonthlyExpenseSource.manual,
    );
    await controller.useAuto();
    expect(
      container.read(effectiveMonthlyExpenseProvider).requireValue.source,
      MonthlyExpenseSource.auto,
    );
  });

  test('window setter clamps to [1, 12]', () async {
    final container = await _container();
    addTearDown(container.dispose);

    final controller = container.read(
      monthlyExpensePreferencesProvider.notifier,
    );
    await controller.setWindow(0);
    expect(container.read(monthlyExpensePreferencesProvider).windowMonths, 1);
    await controller.setWindow(99);
    expect(container.read(monthlyExpensePreferencesProvider).windowMonths, 12);
    await controller.setWindow(6);
    expect(container.read(monthlyExpensePreferencesProvider).windowMonths, 6);
  });
}

DateTime _firstOfMonthBefore(DateTime ref, int months) {
  var year = ref.year;
  var month = ref.month - months;
  while (month <= 0) {
    month += 12;
    year -= 1;
  }
  return DateTime.utc(year, month, 1);
}
