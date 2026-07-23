import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/expense/data/expense_category_providers.dart';
import 'package:naviwealth/features/finance/expense/data/expense_report_providers.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_report_range.dart';
import 'package:naviwealth/features/finance/expense/ui/spending_page.dart';
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
  required String categoryId,
  required Decimal amount,
  required DateTime date,
}) => Expense(
  id: id,
  categoryId: categoryId,
  amount: amount,
  currency: 'CNY',
  tradeDate: date,
  sync: _meta(),
);

ExpenseCategory _category(String id, String name) => ExpenseCategory(
  id: id,
  name: name,
  ledgerAccountId: 'ledger-$id',
  sync: _meta(),
);

Future<ProviderScope> _wrap({
  required Widget child,
  List<Expense> expenses = const [],
  List<ExpenseCategory> categories = const [],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      journalExpensesStreamProvider.overrideWith(
        (ref) => Stream.value(expenses),
      ),
      allExpenseCategoriesProvider.overrideWith(
        (ref) => Stream.value(categories),
      ),
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
  testWidgets('spending renders empty chart states with no data', (
    tester,
  ) async {
    final widget = await _wrap(child: const SpendingPage());
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
    expect(find.byType(SpendingPage), findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(find.byType(SpendingPage)));
    expect(find.text(l10n.expenseReportTotalExpenses), findsOneWidget);
    // Pie + trend both fall back to empty chart states when there's no data.
    expect(find.byType(EmptyChartPlaceholder), findsAtLeastNWidgets(1));
  });

  testWidgets('spending renders pie + trend chart when data present', (
    tester,
  ) async {
    final today = DateTime.now();
    // Use a date safely inside the m3 range (5 days ago) to avoid
    // flakiness when today is early in the month.
    final inMonth = today.subtract(const Duration(days: 5));
    final expenses = [
      _expense(
        id: 'e1',
        categoryId: 'dining',
        amount: Decimal.parse('120'),
        date: inMonth,
      ),
      _expense(
        id: 'e2',
        categoryId: 'transport',
        amount: Decimal.parse('40'),
        date: inMonth,
      ),
    ];

    final categories = [
      _category('dining', '餐饮'),
      _category('transport', '交通'),
    ];

    final widget = await _wrap(
      child: const SpendingPage(),
      expenses: expenses,
      categories: categories,
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
    final reportList = find
        .descendant(
          of: find.byType(SpendingPage),
          matching: find.byType(ListView),
        )
        .first;
    await tester.dragUntilVisible(
      find.byType(NwBarChart),
      reportList,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NwBarChart), findsOneWidget);
  });

  testWidgets('range chips switch the resolved range provider', (tester) async {
    late ProviderContainer container;
    final widget = await _wrap(
      child: Consumer(
        builder: (ctx, ref, _) {
          container = ProviderScope.containerOf(ctx, listen: false);
          return const SpendingPage();
        },
      ),
    );
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // Default selection is m3 ("近 3 月").
    expect(
      container.read(expenseReportRangePresetProvider),
      ExpenseReportRangePreset.m3,
    );

    final l10n = AppLocalizations.of(tester.element(find.byType(SpendingPage)));
    await tester.tap(find.text(l10n.expenseReportRangeThisMonth));
    await tester.pumpAndSettle();
    expect(
      container.read(expenseReportRangePresetProvider),
      ExpenseReportRangePreset.monthToDate,
    );
  });
}
