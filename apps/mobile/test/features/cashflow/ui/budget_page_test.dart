import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/domain/values/money.dart';
import 'package:naviwealth/features/cashflow/domain/budget_summary.dart';
import 'package:naviwealth/features/cashflow/ui/budget_page.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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

void main() {
  testWidgets('renders empty state when no budgets exist', (tester) async {
    await _pump(tester, const []);

    expect(find.text('No budgets yet'), findsOneWidget);
    expect(find.byIcon(FLucideIcons.piggyBank), findsWidgets);
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
  final now = DateTime.now().toUtc();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}
