import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/data/domain/account.dart';
import 'package:naviwealth/data/domain/enums.dart';
import 'package:naviwealth/data/domain/expense.dart';
import 'package:naviwealth/data/domain/hlc.dart';
import 'package:naviwealth/data/domain/sync_meta.dart';
import 'package:naviwealth/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/data/repositories/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/expense/data/expense_report_providers.dart';
import 'package:naviwealth/features/expense/domain/expense_report_range.dart';
import 'package:naviwealth/features/expense/ui/expense_report_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

SyncMeta _meta() => SyncMeta(
      ownerUserId: 'u',
      updatedAt: DateTime.utc(2026, 4, 1),
      updatedByDevice: 't',
      hlc: Hlc.zero('t'),
    );

Expense _expense({
  required String id,
  required String expenseAccountId,
  required Decimal amount,
  required DateTime date,
}) =>
    Expense(
      id: id,
      expenseAccountId: expenseAccountId,
      amount: amount,
      currency: 'CNY',
      tradeDate: date,
      sync: _meta(),
    );

Account _account(String id, String name) => Account(
      id: id,
      type: AccountType.other,
      name: name,
      currency: 'CNY',
      category: AccountCategory.expense,
      sync: _meta(),
    );

Future<ProviderScope> _wrap({
  required Widget child,
  List<Expense> expenses = const [],
  List<Account> accounts = const [],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      journalExpensesStreamProvider.overrideWith((ref) => Stream.value(expenses)),
      accountsStreamProvider.overrideWith((ref) => Stream.value(accounts)),
      // FX rates stream — empty list is fine for single-currency tests.
      fxRatesStreamProvider.overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  testWidgets('expense report renders empty chart states with no data',
      (tester) async {
    final widget = await _wrap(child: const ExpenseReportPage());
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    expect(find.byType(ExpenseReportPage), findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(find.byType(ExpenseReportPage)));
    expect(find.text(l10n.expenseReportTotalExpenses), findsOneWidget);
    // Pie + trend both fall back to empty chart states when there's no data.
    expect(find.byType(EmptyChartPlaceholder), findsAtLeastNWidgets(1));
  });

  testWidgets('expense report renders pie + trend chart when data present',
      (tester) async {
    final today = DateTime.now();
    // Use a date safely inside the m3 range (5 days ago) to avoid
    // flakiness when today is early in the month.
    final inMonth = today.subtract(const Duration(days: 5));
    final expenses = [
      _expense(
        id: 'e1',
        expenseAccountId: 'food',
        amount: Decimal.parse('120'),
        date: inMonth,
      ),
      _expense(
        id: 'e2',
        expenseAccountId: 'transport',
        amount: Decimal.parse('40'),
        date: inMonth,
      ),
    ];

    final accounts = [
      _account('food', '餐饮'),
      _account('transport', '交通'),
    ];

    final widget = await _wrap(
      child: const ExpenseReportPage(),
      expenses: expenses,
      accounts: accounts,
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // Pie chart mounts above the fold.
    expect(find.byType(NwPieChart), findsOneWidget);
    expect(find.text('餐饮'), findsWidgets);
    expect(find.text('交通'), findsWidgets);

    // Scroll the report ListView to bring the trend chart into the
    // viewport. The page nests several Scrollables (legend ListView, etc.)
    // so we scope the drag to the outermost ListView.
    final reportList =
        find.descendant(of: find.byType(ExpenseReportPage), matching: find.byType(ListView)).first;
    await tester.dragUntilVisible(
      find.byType(NwBarChart),
      reportList,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NwBarChart), findsOneWidget);
  });

  testWidgets('range chips switch the resolved range provider',
      (tester) async {
    late ProviderContainer container;
    final widget = await _wrap(
      child: Consumer(builder: (ctx, ref, _) {
        container = ProviderScope.containerOf(ctx, listen: false);
        return const ExpenseReportPage();
      }),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // Default selection is m3 ("近 3 月").
    expect(
      container.read(expenseReportRangePresetProvider),
      ExpenseReportRangePreset.m3,
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(ExpenseReportPage)));
    await tester.tap(find.text(l10n.expenseReportRangeThisMonth));
    await tester.pumpAndSettle();
    expect(
      container.read(expenseReportRangePresetProvider),
      ExpenseReportRangePreset.monthToDate,
    );
  });
}
