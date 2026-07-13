import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';

import 'activity_feed_query.dart';

const int kActivityFeedPageSize = 50;

final activityFeedQueryProvider =
    StateNotifierProvider<ActivityFeedQueryController, ActivityFeedQuery>(
      (ref) => ActivityFeedQueryController(),
    );

final activityFeedProvider = StreamProvider.autoDispose<ActivityFeedPage>((
  ref,
) {
  final query = ref.watch(activityFeedQueryProvider);
  final accountsAsync = ref.watch(allAccountsStreamProvider);

  if (accountsAsync.hasError) {
    return Stream.error(
      accountsAsync.error!,
      accountsAsync.stackTrace ?? StackTrace.current,
    );
  }
  final accounts = accountsAsync.value;
  if (accounts == null) return const Stream<ActivityFeedPage>.empty();

  final accountsById = <String, Account>{
    for (final account in accounts) account.id: account,
  };
  final accountCategories = {
    for (final account in accounts) account.id: account.category,
  };
  return Stream.fromFuture(ref.watch(journalEntryRepositoryProvider.future))
      .asyncExpand(
        (repo) => repo.watchActivityFeed(
          from: query.dateRange?.start,
          to: query.dateRange?.end,
          accountIds: query.accountIds,
          kinds: query.kinds.map(entryKindFromActivityKind).toSet(),
          accountCategories: accountCategories,
          pageSize: query.pageSize,
        ),
      )
      .map((page) {
        final needle = query.searchText.trim().toLowerCase();
        final entries = needle.isEmpty
            ? page.entries
            : page.entries
                  .where((entry) {
                    final narration = entry.entry.narration.toLowerCase();
                    final payee = (entry.entry.payee ?? '').toLowerCase();
                    return narration.contains(needle) || payee.contains(needle);
                  })
                  .toList(growable: false);
        return ActivityFeedPage(
          entries: entries,
          totalCount: entries.length,
          hasMore: page.hasMore,
          isFiltered: query.hasFilters,
          accountsById: accountsById,
        );
      });
});

class ActivityFeedQueryController extends StateNotifier<ActivityFeedQuery> {
  ActivityFeedQueryController() : super(const ActivityFeedQuery());

  void setQuery(ActivityFeedQuery query) {
    state = query.copyWith(pageSize: kActivityFeedPageSize);
  }

  void mutateQuery(ActivityFeedQuery Function(ActivityFeedQuery query) mutate) {
    state = mutate(state).copyWith(pageSize: kActivityFeedPageSize);
  }

  void loadMore() {
    state = state.copyWith(pageSize: state.pageSize + kActivityFeedPageSize);
  }

  void refresh() {
    state = state.copyWith();
  }

  void clearFilters() {
    state = ActivityFeedQuery(pageSize: state.pageSize);
  }
}
