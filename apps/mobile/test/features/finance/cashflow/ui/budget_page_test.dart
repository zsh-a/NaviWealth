import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_summary.dart';
import 'package:naviwealth/features/finance/cashflow/ui/budget_page.dart';
import 'package:naviwealth/features/finance/data/repositories/budget_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/expense/data/expense_category_providers.dart';
import 'package:naviwealth/features/finance/expense/domain/expense_category.dart';
import 'package:naviwealth/features/finance/expense/ui/expense_category_picker.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

/// Build a [BudgetRow] without going through the live Drift database —
/// the page only reads display fields, so a hand-rolled row exercises
/// the rendering path without spinning up the schema.
BudgetRow _row({
  required String categoryId,
  required String periodMonth,
  required String amount,
  String currency = 'CNY',
  String? note,
}) => BudgetRow(
  id: '$periodMonth/$categoryId',
  categoryId: categoryId,
  periodMonth: periodMonth,
  amount: Decimal.parse(amount),
  currency: currency,
  note: note,
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 5, 24),
  updatedByDevice: 'd',
  hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
  deletedAt: null,
);

Future<void> _pump(WidgetTester tester, List<BudgetRow> rows) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        allExpenseCategoriesProvider.overrideWith(
          (ref) => Stream.value([_expenseCategory()]),
        ),
        // Replace the family stream with a single-shot stream that emits
        // the canned rows once. No Drift, no DB, no animation never-end.
        budgetsForMonthProvider.overrideWith((ref, periodMonth) async* {
          yield rows
              .where((r) => r.periodMonth == periodMonth && r.deletedAt == null)
              .toList();
        }),
        monthlyBudgetSummaryProvider.overrideWith((ref, periodMonth) {
          final filtered = rows
              .where((r) => r.periodMonth == periodMonth && r.deletedAt == null)
              .toList();
          final currency = filtered.isEmpty
              ? 'CNY'
              : filtered.first.currency.toUpperCase();
          var total = Decimal.zero;
          final categories = <CategoryBudgetStatus>[];
          for (final row in filtered) {
            total += row.amount;
            final spent = row.categoryId == 'cat-food'
                ? Decimal.parse('1200')
                : Decimal.zero;
            categories.add(
              CategoryBudgetStatus(
                categoryId: row.categoryId,
                budgeted: Money(row.amount, row.currency),
                spent: Money(spent, row.currency),
              ),
            );
          }
          return AsyncValue.data((
            summary: MonthlyBudgetSummary(
              periodMonth: periodMonth,
              currency: currency,
              totalBudgeted: Money(total, currency),
              totalSpent: Money(
                categories.fold<Decimal>(
                  Decimal.zero,
                  (sum, item) => sum + item.spent.amount,
                ),
                currency,
              ),
              categories: categories,
            ),
            mismatchedCount: 0,
          ));
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en', 'US'),
        home: const PlanBudgetPage(),
      ),
    ),
  );
  // Two pumps drain the single-emission stream and let the data branch
  // build. We deliberately avoid pumpAndSettle — FCircularProgress
  // animates forever before the StreamProvider yields.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpLive(
  WidgetTester tester, {
  required BudgetRepository repository,
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        budgetRepositoryProvider.overrideWith((ref) async => repository),
        allExpenseCategoriesProvider.overrideWith(
          (ref) => Stream.value([_expenseCategory()]),
        ),
        monthlyBudgetSummaryProvider.overrideWith((ref, periodMonth) {
          return AsyncValue.data((
            summary: MonthlyBudgetSummary(
              periodMonth: periodMonth,
              currency: 'CNY',
              totalBudgeted: Money.zero('CNY'),
              totalSpent: Money.zero('CNY'),
              categories: const [],
            ),
            mismatchedCount: 0,
          ));
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en', 'US'),
        home: const PlanBudgetPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('renders empty state when no budgets exist', (tester) async {
    await _pump(tester, const []);

    expect(find.text('No budgets yet'), findsOneWidget);
    expect(find.text('Set first budget'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.piggyBank), findsWidgets);
  });

  testWidgets('switches the active budget month', (tester) async {
    await _pump(tester, const []);
    final now = DateTime.now();
    final next = DateTime(now.year, now.month + 1);
    final nextKey =
        '${next.year}-${next.month.toString().padLeft(2, '0')} budgets';

    await tester.tap(find.byIcon(FLucideIcons.chevronRight));
    await tester.pumpAndSettle();

    expect(find.text(nextKey), findsOneWidget);
  });

  testWidgets('creates the first budget from the empty state', (tester) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = BudgetRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
      ownerUserId: 'u-test',
    );
    await _pumpLive(tester, repository: repository);

    await tester.tap(find.text('Set first budget'));
    await tester.pumpAndSettle();
    expect(find.text('New budget'), findsOneWidget);

    await tester.tap(find.byType(ExpenseCategoryPicker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(FTextField, 'Amount (CNY)'),
      '1800',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final stored = await repository.findForCategoryMonth(
      categoryId: 'expense-dining',
      periodMonth: _currentMonthKey(),
    );
    expect(stored?.amount, Decimal.parse('1800'));
    expect(stored?.currency, 'CNY');
    expect(find.text('Dining'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('deletes an existing budget from its edit sheet', (tester) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = BudgetRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
      ownerUserId: 'u-test',
    );
    await repository.create(
      categoryId: 'expense-dining',
      periodMonth: _currentMonthKey(),
      amount: Decimal.parse('1200'),
      currency: 'CNY',
    );
    await _pumpLive(tester, repository: repository);

    await tester.tap(find.text('Dining'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(FLucideIcons.trash2));
    await tester.pumpAndSettle();
    expect(find.text('Delete this budget?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    final stored = await repository.findForCategoryMonth(
      categoryId: 'expense-dining',
      periodMonth: _currentMonthKey(),
    );
    expect(stored, isNull);
    expect(find.text('No budgets yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('copies missing budgets from the previous month', (tester) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = BudgetRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
      ownerUserId: 'u-test',
    );
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month - 1);
    final previousKey =
        '${previous.year}-${previous.month.toString().padLeft(2, '0')}';
    await repository.create(
      categoryId: 'expense-dining',
      periodMonth: previousKey,
      amount: Decimal.parse('1600'),
      currency: 'CNY',
    );
    await _pumpLive(tester, repository: repository);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(FLucideIcons.copy));
    await tester.pumpAndSettle();

    final copied = await repository.findForCategoryMonth(
      categoryId: 'expense-dining',
      periodMonth: _currentMonthKey(),
    );
    expect(copied?.amount, Decimal.parse('1600'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('renders budgets for the current UTC month + total roll-up', (
    tester,
  ) async {
    final monthKey = _currentMonthKey();
    await _pump(tester, [
      _row(categoryId: 'cat-food', periodMonth: monthKey, amount: '1500'),
      _row(categoryId: 'cat-rent', periodMonth: monthKey, amount: '5000'),
    ]);

    expect(find.text('cat-food'), findsOneWidget);
    expect(find.text('cat-rent'), findsOneWidget);
    expect(find.textContaining('6,500'), findsWidgets);
    expect(find.textContaining('Spent 1200 of 6500 CNY'), findsOneWidget);
    expect(find.textContaining('300 CNY left'), findsOneWidget);
    expect(find.text('No budgets yet'), findsNothing);
  });

  testWidgets('ignores budgets for other months', (tester) async {
    // Far-past month — the provider override filters by periodMonth and
    // returns empty for the page's current-month key.
    await _pump(tester, [
      _row(categoryId: 'cat-historical', periodMonth: '2020-01', amount: '999'),
    ]);

    expect(find.text('cat-historical'), findsNothing);
    expect(find.text('No budgets yet'), findsOneWidget);
  });

  testWidgets('drops tombstoned rows in the same month', (tester) async {
    final monthKey = _currentMonthKey();
    final tombstone = _row(
      categoryId: 'cat-tombstone',
      periodMonth: monthKey,
      amount: '300',
    ).copyWith(deletedAt: Value(DateTime.now()));
    await _pump(tester, [tombstone]);

    expect(find.text('cat-tombstone'), findsNothing);
    expect(find.text('No budgets yet'), findsOneWidget);
  });
}

String _currentMonthKey() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

ExpenseCategory _expenseCategory() => ExpenseCategory(
  id: 'expense-dining',
  name: 'Dining',
  ledgerAccountId: 'system-account:u-test:expense:dining',
  sync: SyncMeta(
    ownerUserId: 'u',
    updatedAt: DateTime.utc(2026, 5, 24),
    updatedByDevice: 'd',
    hlc: const Hlc(wallMillis: 1, counter: 0, nodeId: 'd'),
  ),
);
