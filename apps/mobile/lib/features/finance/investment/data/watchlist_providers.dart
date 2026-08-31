import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/data/market/market_data_providers.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';

import 'watchlist_repository.dart';

final watchlistRepositoryProvider = FutureProvider<WatchlistRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return WatchlistRepository(db: db, outbox: outbox, stamper: stamper);
});

final watchlistItemsProvider = StreamProvider.autoDispose<List<WatchlistItem>>((
  ref,
) async* {
  final repo = await ref.watch(watchlistRepositoryProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  yield* repo.watchActive(ownerUserId);
});

final watchlistCollectionsProvider =
    StreamProvider.autoDispose<List<WatchlistCollection>>((ref) async* {
      final repo = await ref.watch(watchlistRepositoryProvider.future);
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repo.watchCollections(ownerUserId);
    });

final watchlistCollectionMembersProvider =
    StreamProvider.autoDispose<List<WatchlistCollectionMember>>((ref) async* {
      final repo = await ref.watch(watchlistRepositoryProvider.future);
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      yield* repo.watchCollectionMembers(ownerUserId);
    });

class WatchlistScope {
  const WatchlistScope.all() : collectionId = null, ungrouped = false;

  const WatchlistScope.ungrouped() : collectionId = null, ungrouped = true;

  const WatchlistScope.collection(this.collectionId) : ungrouped = false;

  final String? collectionId;
  final bool ungrouped;

  bool get isAll => collectionId == null && !ungrouped;

  @override
  bool operator ==(Object other) =>
      other is WatchlistScope &&
      other.collectionId == collectionId &&
      other.ungrouped == ungrouped;

  @override
  int get hashCode => Object.hash(collectionId, ungrouped);
}

class WatchlistCollectionCounts {
  const WatchlistCollectionCounts({
    required this.all,
    required this.ungrouped,
    required this.byCollectionId,
  });

  factory WatchlistCollectionCounts.from({
    required Iterable<WatchlistItem> items,
    required Iterable<WatchlistCollectionMember> members,
  }) {
    final itemIds = items.map((item) => item.id).toSet();
    final groupedItemIds = <String>{};
    final itemsByCollectionId = <String, Set<String>>{};
    for (final member in members) {
      if (!itemIds.contains(member.watchlistItemId)) continue;
      groupedItemIds.add(member.watchlistItemId);
      (itemsByCollectionId[member.collectionId] ??= <String>{}).add(
        member.watchlistItemId,
      );
    }
    return WatchlistCollectionCounts(
      all: itemIds.length,
      ungrouped: itemIds.difference(groupedItemIds).length,
      byCollectionId: Map<String, int>.unmodifiable({
        for (final entry in itemsByCollectionId.entries)
          entry.key: entry.value.length,
      }),
    );
  }

  final int all;
  final int ungrouped;
  final Map<String, int> byCollectionId;

  int forCollection(String collectionId) => byCollectionId[collectionId] ?? 0;
}

final watchlistItemsForScopeProvider = FutureProvider.autoDispose
    .family<List<WatchlistItem>, WatchlistScope>((ref, scope) async {
      final items = await ref.watch(watchlistItemsProvider.future);
      if (scope.isAll) return items;
      final members = await ref.watch(
        watchlistCollectionMembersProvider.future,
      );
      if (scope.ungrouped) {
        final allGroupedIds = members
            .map((member) => member.watchlistItemId)
            .toSet();
        return items
            .where((item) => !allGroupedIds.contains(item.id))
            .toList(growable: false);
      }
      final memberItemIds = <String>{
        for (final member in members)
          if (member.collectionId == scope.collectionId) member.watchlistItemId,
      };
      final memberPositionByItemId = <String, int>{};
      for (final member in members) {
        if (member.collectionId != scope.collectionId) continue;
        memberPositionByItemId[member.watchlistItemId] = member.sortRank;
      }
      final scopedItems = items
          .where((item) => memberItemIds.contains(item.id))
          .toList();
      scopedItems.sort((left, right) {
        final rankComparison = memberPositionByItemId[left.id]!.compareTo(
          memberPositionByItemId[right.id]!,
        );
        if (rankComparison != 0) return rankComparison;
        return left.addedAt.compareTo(right.addedAt);
      });
      return List<WatchlistItem>.unmodifiable(scopedItems);
    });

final watchlistQuoteSnapshotsProvider =
    FutureProvider.autoDispose<List<WatchlistQuoteSnapshot>>((ref) async {
      final items = await ref.watch(watchlistItemsProvider.future);
      return _loadQuoteSnapshots(ref, items);
    });

final watchlistQuoteSnapshotsForScopeProvider = FutureProvider.autoDispose
    .family<List<WatchlistQuoteSnapshot>, WatchlistScope>((ref, scope) async {
      final items = await ref.watch(
        watchlistItemsForScopeProvider(scope).future,
      );
      return _loadQuoteSnapshots(ref, items);
    });

class WatchlistQuoteSnapshot {
  const WatchlistQuoteSnapshot({required this.item, this.response, this.error});

  final WatchlistItem item;
  final MarketResponse<Quote>? response;
  final Object? error;

  Quote? get quote => response?.data;
  bool get hasError => error != null;
}

class WatchlistQuoteSummary {
  const WatchlistQuoteSummary({
    required this.symbolCount,
    required this.availableQuoteCount,
    required this.advancingCount,
    required this.decliningCount,
  });

  factory WatchlistQuoteSummary.fromSnapshots({
    required int symbolCount,
    required Iterable<WatchlistQuoteSnapshot> snapshots,
  }) {
    var availableQuoteCount = 0;
    var advancingCount = 0;
    var decliningCount = 0;
    for (final snapshot in snapshots) {
      final quote = snapshot.quote;
      if (quote == null) continue;
      availableQuoteCount++;
      final change = quote.change;
      if (change == null) continue;
      if (change > Decimal.zero) {
        advancingCount++;
      } else if (change < Decimal.zero) {
        decliningCount++;
      }
    }
    return WatchlistQuoteSummary(
      symbolCount: symbolCount,
      availableQuoteCount: availableQuoteCount,
      advancingCount: advancingCount,
      decliningCount: decliningCount,
    );
  }

  final int symbolCount;
  final int availableQuoteCount;
  final int advancingCount;
  final int decliningCount;
}

enum WatchlistSortOrder { defaultOrder, gainers, decliners, symbol }

enum WatchlistAlertFilter { all, configured, none }

enum WatchlistFreshnessFilter { all, live, cached, stale, unavailable }

class WatchlistFilter {
  const WatchlistFilter({
    this.market,
    this.alerts = WatchlistAlertFilter.all,
    this.freshness = WatchlistFreshnessFilter.all,
  });

  final AssetMarket? market;
  final WatchlistAlertFilter alerts;
  final WatchlistFreshnessFilter freshness;

  bool get isDefault =>
      market == null &&
      alerts == WatchlistAlertFilter.all &&
      freshness == WatchlistFreshnessFilter.all;
}

List<WatchlistItem> filterWatchlistItems({
  required List<WatchlistItem> items,
  required Iterable<WatchlistQuoteSnapshot> snapshots,
  required WatchlistFilter filter,
}) {
  if (filter.isDefault) return List<WatchlistItem>.of(items);
  final snapshotsByItemId = <String, WatchlistQuoteSnapshot>{
    for (final snapshot in snapshots) snapshot.item.id: snapshot,
  };
  return items
      .where((item) {
        if (filter.market != null && item.market != filter.market) return false;
        final hasConfiguredAlert =
            item.alertRules.enabled && item.alertRules.hasRule;
        if (filter.alerts == WatchlistAlertFilter.configured &&
            !hasConfiguredAlert) {
          return false;
        }
        if (filter.alerts == WatchlistAlertFilter.none && hasConfiguredAlert) {
          return false;
        }
        final snapshot = snapshotsByItemId[item.id];
        final matchesFreshness = switch (filter.freshness) {
          WatchlistFreshnessFilter.all => true,
          WatchlistFreshnessFilter.live =>
            snapshot?.quote != null &&
                snapshot?.response?.freshness == DataFreshness.live,
          WatchlistFreshnessFilter.cached =>
            snapshot?.quote != null &&
                snapshot?.response?.freshness == DataFreshness.cachedFresh,
          WatchlistFreshnessFilter.stale =>
            snapshot?.quote != null &&
                snapshot?.response?.freshness == DataFreshness.stale,
          WatchlistFreshnessFilter.unavailable => snapshot?.quote == null,
        };
        return matchesFreshness;
      })
      .toList(growable: false);
}

List<WatchlistItem> sortWatchlistItems({
  required List<WatchlistItem> items,
  required Iterable<WatchlistQuoteSnapshot> snapshots,
  required WatchlistSortOrder order,
}) {
  final sorted = List<WatchlistItem>.of(items);
  if (order == WatchlistSortOrder.defaultOrder || sorted.length < 2) {
    return sorted;
  }
  final originalIndex = <String, int>{
    for (var index = 0; index < items.length; index++) items[index].id: index,
  };
  if (order == WatchlistSortOrder.symbol) {
    sorted.sort((left, right) {
      final symbolComparison = left.displaySymbol.compareTo(
        right.displaySymbol,
      );
      if (symbolComparison != 0) return symbolComparison;
      return originalIndex[left.id]!.compareTo(originalIndex[right.id]!);
    });
    return sorted;
  }

  final changesByItemId = <String, Decimal?>{
    for (final snapshot in snapshots)
      snapshot.item.id: snapshot.quote?.changePercent,
  };
  sorted.sort((left, right) {
    final leftChange = changesByItemId[left.id];
    final rightChange = changesByItemId[right.id];
    if (leftChange == null && rightChange != null) return 1;
    if (leftChange != null && rightChange == null) return -1;
    if (leftChange != null && rightChange != null) {
      final changeComparison = leftChange.compareTo(rightChange);
      if (changeComparison != 0) {
        return order == WatchlistSortOrder.gainers
            ? -changeComparison
            : changeComparison;
      }
    }
    return originalIndex[left.id]!.compareTo(originalIndex[right.id]!);
  });
  return sorted;
}

Future<List<WatchlistQuoteSnapshot>> _loadQuoteSnapshots(
  Ref ref,
  List<WatchlistItem> items,
) async {
  if (items.isEmpty) return const [];
  final service = await ref.watch(marketDataServiceProvider.future);
  final snapshots = <WatchlistQuoteSnapshot>[];
  // Keep requests sequential: some configured providers have strict
  // per-minute limits and MarketDataService already handles cache fallback.
  for (final item in items) {
    snapshots.add(await _fetchSnapshot(service, item));
  }
  return snapshots;
}

Future<WatchlistQuoteSnapshot> _fetchSnapshot(
  MarketDataService service,
  WatchlistItem item,
) async {
  try {
    final response = await service.getQuote(item.symbol, market: item.market);
    return WatchlistQuoteSnapshot(item: item, response: response);
  } catch (error) {
    return WatchlistQuoteSnapshot(item: item, error: error);
  }
}
