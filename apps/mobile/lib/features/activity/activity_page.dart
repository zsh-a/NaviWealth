import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../accounts/accounts_page.dart';
import '../expense/ui/expense_list_page.dart';
import 'ui/activity_feed.dart';

/// Activity tab — umbrella page with a segmented control toggling
/// between Expenses, Accounts, and Activity Feed.
class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

enum _ActivityTab { expenses, accounts, feed }

class _ActivityPageState extends ConsumerState<ActivityPage> {
  _ActivityTab _tab = _ActivityTab.expenses;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.navActivity),
        actions: [
          if (_tab == _ActivityTab.accounts)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: l10n.accountsTransferAction,
              onPressed: () => context.push('/activity/accounts/transfer'),
            ),
          if (_tab == _ActivityTab.accounts)
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: l10n.accountsJournalAction,
              onPressed: () => context.push('/activity/accounts/journal'),
            ),
          if (_tab == _ActivityTab.expenses)
            IconButton(
              icon: const Icon(Icons.bar_chart_outlined),
              tooltip: l10n.expenseReportTitle,
              onPressed: () => context.push('/activity/expenses/report'),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _SegmentedControl(
            current: _tab,
            onChanged: (_ActivityTab t) => setState(() => _tab = t),
            l10n: l10n,
          ),
        ),
      ),
      body: _tab == _ActivityTab.expenses
          ? const ExpenseListPage(embedded: true)
          : _tab == _ActivityTab.accounts
              ? const AccountsPage(embedded: true)
              : const ActivityFeed(),
      floatingActionButton: _tab == _ActivityTab.expenses
          ? ScrollAwareFab(
              child: AppFab(
                onPressed: () => context.push('/activity/expenses/new'),
                child: const Icon(Icons.add),
              ),
            )
          : _tab == _ActivityTab.accounts
              ? ScrollAwareFab(
                  child: AppFab(
                    onPressed: () => context.push('/activity/accounts/new'),
                    child: const Icon(Icons.add),
                  ),
                )
              : null,
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl({
    required this.current,
    required this.onChanged,
    required this.l10n,
  });

  final _ActivityTab current;
  final ValueChanged<_ActivityTab> onChanged;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = [
      l10n.navExpenses,
      l10n.navAccounts,
      l10n.activityFeedTab,
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.s16),
      child: Row(
        children: List.generate(segments.length, (i) {
          final tab = _ActivityTab.values[i];
          final selected = tab == current;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(tab),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    segments[i],
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: Spacing.s4),
                  AnimatedContainer(
                    duration: Motion.fast,
                    curve: Motion.standardDecelerate,
                    height: 2,
                    width: selected ? 24 : 0,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: Radii.brXxl,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
