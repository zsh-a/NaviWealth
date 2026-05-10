import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../app/route_paths.dart';
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

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.navActivity),
        suffixes: [
          if (_tab == _ActivityTab.accounts)
            FHeaderAction(
              icon: const Icon(Icons.add_card_outlined),
              onPress: () => context.push(AppRoutes.accountNew),
            ),
          if (_tab == _ActivityTab.accounts)
            FHeaderAction(
              icon: const Icon(Icons.swap_horiz),
              onPress: () => context.push(AppRoutes.accountTransfer),
            ),
          if (_tab == _ActivityTab.accounts)
            FHeaderAction(
              icon: const Icon(Icons.receipt_long_outlined),
              onPress: () => context.push(AppRoutes.accountJournal),
            ),
          if (_tab == _ActivityTab.expenses)
            FHeaderAction(
              icon: const Icon(Icons.bar_chart_outlined),
              onPress: () => context.push(AppRoutes.expenseReport),
            ),
          if (_tab == _ActivityTab.feed)
            FHeaderAction(
              icon: const Icon(Icons.filter_list_outlined),
              onPress: () => ActivityFeedFilterSheet.show(context),
            ),
        ],
      ),
      childPad: false,
      child: Material(
          color: Colors.transparent,
          child: _tab == _ActivityTab.expenses
          ? const ExpenseListPage(embedded: true)
          : _tab == _ActivityTab.accounts
          ? const AccountsPage(embedded: true)
          : const ActivityFeed(),
        ),
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

