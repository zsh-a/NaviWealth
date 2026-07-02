import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/expense.dart';
import 'package:naviwealth/features/finance/expense/ui/expense_list_content.dart';
import 'package:naviwealth/features/finance/expense/ui/expense_list_models.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('selection toolbar explains selected expenses', (tester) async {
    final expenses = [
      _expense(id: 'exp-1', note: 'Coffee'),
      _expense(id: 'exp-2', note: 'Lunch'),
    ];
    final account = _account('food', 'Food');
    var explained = const <Expense>[];
    var opened = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _SelectionHarness(
          expenses: expenses,
          accounts: {'food': account},
          onExplain: (selected) => explained = selected,
          onOpen: (_) => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Explain selected'), findsNothing);

    await tester.tap(find.byType(FCheckbox).first);
    await tester.pumpAndSettle();

    expect(opened, 0);
    expect(find.text('1 transaction selected'), findsOneWidget);
    expect(find.text('Explain selected'), findsOneWidget);

    await tester.tap(find.text('Explain selected'));
    await tester.pumpAndSettle();

    expect(explained.map((expense) => expense.id), ['exp-1']);
  });
}

class _SelectionHarness extends StatefulWidget {
  const _SelectionHarness({
    required this.expenses,
    required this.accounts,
    required this.onExplain,
    required this.onOpen,
  });

  final List<Expense> expenses;
  final Map<String, Account> accounts;
  final ValueChanged<List<Expense>> onExplain;
  final ValueChanged<Expense> onOpen;

  @override
  State<_SelectionHarness> createState() => _SelectionHarnessState();
}

class _SelectionHarnessState extends State<_SelectionHarness> {
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final selected = widget.expenses
        .where((expense) => _selectedIds.contains(expense.id))
        .toList(growable: false);
    return Scaffold(
      body: Column(
        children: [
          if (selected.isNotEmpty)
            ExpenseSelectionToolbar(
              selectedCount: selected.length,
              onExplain: () => widget.onExplain(selected),
              onClear: () => setState(_selectedIds.clear),
            ),
          Expanded(
            child: ExpenseGroupedList(
              expenses: widget.expenses,
              expenseAccountById: widget.accounts,
              grouping: ExpenseGrouping.month,
              onTap: widget.onOpen,
              selectedExpenseIds: _selectedIds,
              onToggleSelected: (expense) {
                setState(() {
                  if (!_selectedIds.add(expense.id)) {
                    _selectedIds.remove(expense.id);
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

Expense _expense({required String id, required String note}) => Expense(
  id: id,
  expenseAccountId: 'food',
  amount: Decimal.fromInt(12),
  currency: 'CNY',
  tradeDate: DateTime.utc(2026, 6, 19),
  note: note,
  sync: _meta(),
);

Account _account(String id, String name) => Account(
  id: id,
  type: AccountCategory.asset,
  name: name,
  currency: 'CNY',
  category: AccountSide.expense,
  sync: _meta(),
);

SyncMeta _meta() => SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 6, 19),
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);
