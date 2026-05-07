import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../accounts/accounts_page.dart';
import '../expense/ui/expense_list_page.dart';
import 'data/activity_feed_provider.dart';
import 'data/activity_feed_query.dart';
import 'ui/activity_feed.dart';
import 'ui/activity_feed_filter_sheet.dart';

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
  bool _hydratedFromUrl = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydratedFromUrl) return;
    _hydratedFromUrl = true;
    final uri = GoRouter.of(context).routeInformationProvider.value.uri;
    if (uri.queryParameters['tab'] == 'feed') {
      _tab = _ActivityTab.feed;
    }
    final query = ActivityFeedQuery.fromUri(uri);
    if (query.hasFilters) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(activityFeedQueryProvider.notifier).setQuery(query);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<ActivityFeedQuery>(activityFeedQueryProvider, (_, next) {
      if (!mounted || _tab != _ActivityTab.feed) return;
      _replaceActivityUrl(query: next);
    });

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.navActivity),
        actions: [
          if (_tab == _ActivityTab.accounts)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: l10n.accountsTransferAction,
              onPressed: () => context.push(AppRoutes.accountTransfer),
            ),
          if (_tab == _ActivityTab.accounts)
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: l10n.accountsJournalAction,
              onPressed: () => context.push(AppRoutes.accountJournal),
            ),
          if (_tab == _ActivityTab.expenses)
            IconButton(
              icon: const Icon(Icons.bar_chart_outlined),
              tooltip: l10n.expenseReportTitle,
              onPressed: () => context.push(AppRoutes.expenseReport),
            ),
          if (_tab == _ActivityTab.feed)
            IconButton(
              icon: const Icon(Icons.filter_list_outlined),
              tooltip: l10n.activityFeedFilterTitle,
              onPressed: () => ActivityFeedFilterSheet.show(context),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _SegmentedControl(
            current: _tab,
            onChanged: (_ActivityTab t) {
              setState(() => _tab = t);
              _replaceActivityUrl(query: ref.read(activityFeedQueryProvider));
            },
            l10n: l10n,
          ),
        ),
      ),
      body: _tab == _ActivityTab.expenses
          ? const ExpenseListPage(embedded: true)
          : _tab == _ActivityTab.accounts
          ? const AccountsPage(embedded: true)
          : const ActivityFeed(),
    );
  }

  void _replaceActivityUrl({required ActivityFeedQuery query}) {
    final router = GoRouter.of(context);
    final current = router.routeInformationProvider.value.uri;
    final params = <String, String>{...current.queryParameters};
    params.remove('accounts');
    params.remove('kinds');
    params.remove('from');
    params.remove('to');
    params.remove('tab');
    if (_tab == _ActivityTab.feed) {
      params['tab'] = 'feed';
      params.addAll(query.toQueryParameters());
    }
    final next = current.replace(
      path: AppRoutes.activity,
      queryParameters: params.isEmpty ? null : params,
    );
    if (next.toString() != current.toString()) {
      router.replace<void>(next.toString());
    }
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
    final segments = [l10n.navExpenses, l10n.navAccounts, l10n.activityFeedTab];

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
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
