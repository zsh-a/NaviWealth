import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
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

  testWidgets('long expense content does not overflow a narrow layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final expense = Expense(
      id: 'exp-long',
      expenseAccountId: 'food',
      amount: Decimal.parse('12345678901234567890.12'),
      currency: 'CNY',
      tradeDate: DateTime.utc(2026, 7, 12),
      note: 'Expense with a very long mixed-language note that must truncate',
      sync: _meta(),
    );
    final account = _account('food', '餐饮与日常生活消费的超长分类名称');
    final keywordController = TextEditingController(text: 'Expense');
    addTearDown(keywordController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FTheme(
          data: buildAppForuiTheme(brightness: Brightness.light, touch: false),
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: Column(
                children: [
                  ExpenseFiltersBar(
                    accounts: [account],
                    expenseAccountById: {'food': account},
                    filters: const ExpenseFilters(expenseAccountId: 'food'),
                    keywordController: keywordController,
                    onChanged: (_) {},
                  ),
                  Expanded(
                    child: ExpenseGroupedList(
                      expenses: [expense],
                      expenseAccountById: {'food': account},
                      grouping: ExpenseGrouping.month,
                      onTap: (_) {},
                      selectedExpenseIds: const <String>{},
                      onToggleSelected: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
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
