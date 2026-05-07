import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../data/domain/account.dart';
import '../../../data/repositories/journal_entry_providers.dart';
import '../../../data/repositories/providers.dart';
import 'activity_feed_query.dart';

const int kActivityFeedPageSize = 50;

final activityFeedQueryProvider =
    StateNotifierProvider<ActivityFeedQueryController, ActivityFeedQuery>(
      (ref) => ActivityFeedQueryController(),
    );

final activityFeedProvider = Provider<AsyncValue<ActivityFeedPage>>((ref) {
  final query = ref.watch(activityFeedQueryProvider);
  final entriesAsync = ref.watch(journalEntriesWithPostingsStreamProvider);
  final accountsAsync = ref.watch(accountsStreamProvider);

  if (entriesAsync.isLoading || accountsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (entriesAsync.hasError) {
    return AsyncValue.error(
      entriesAsync.error!,
      entriesAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (accountsAsync.hasError) {
    return AsyncValue.error(
      accountsAsync.error!,
      accountsAsync.stackTrace ?? StackTrace.current,
    );
  }

  final accountsById = <String, Account>{
    for (final account in accountsAsync.value ?? const <Account>[])
      account.id: account,
  };
  final filtered = filterActivityEntries(
    entries: entriesAsync.value ?? const [],
    query: query,
    accountsById: accountsById,
  );
  final visibleCount = filtered.length < query.pageSize
      ? filtered.length
      : query.pageSize;
  return AsyncValue.data(
    ActivityFeedPage(
      entries: filtered.take(visibleCount).toList(growable: false),
      totalCount: filtered.length,
      hasMore: visibleCount < filtered.length,
      isFiltered: query.hasFilters,
    ),
  );
});

class ActivityFeedQueryController extends StateNotifier<ActivityFeedQuery> {
  ActivityFeedQueryController() : super(const ActivityFeedQuery());

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
