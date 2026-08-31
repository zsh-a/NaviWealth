import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/forms/form_dirty_guard.dart';
import 'package:naviwealth/core/forms/form_submission.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/investment/domain/watchlist_collection_analysis.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/shared/ui/forms/symbol_field.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_providers.dart';
import '../data/watchlist_repository.dart';
import '../data/watchlist_view_preferences.dart';
import 'watchlist_simulation_section.dart';

const _pollInterval = Duration(minutes: 5);
const _collectionQueryKey = 'collection';
const _ungroupedQueryValue = 'ungrouped';
const _sortQueryKey = 'sort';
const _gainersSortQueryValue = 'change-desc';
const _declinersSortQueryValue = 'change-asc';
const _symbolSortQueryValue = 'symbol';
const _marketFilterQueryKey = 'market';
const _alertFilterQueryKey = 'alerts';
const _freshnessFilterQueryKey = 'freshness';

class WatchlistPage extends ConsumerStatefulWidget {
  const WatchlistPage({super.key});

  @override
  ConsumerState<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends ConsumerState<WatchlistPage> {
  Timer? _pollTimer;
  final Set<String> _alertSignatures = {};

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (mounted) {
        ref.invalidate(watchlistQuoteSnapshotsProvider);
        ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allItems = ref.watch(watchlistItemsProvider);
    final collectionsAsync = ref.watch(watchlistCollectionsProvider);
    final membersAsync = ref.watch(watchlistCollectionMembersProvider);
    final collections = collectionsAsync.value ?? const <WatchlistCollection>[];
    final viewPreferences = ref.watch(watchlistViewPreferencesProvider);
    final preferredScope = viewPreferences.scope;
    final requestedScope = _watchlistScopeOf(context, fallback: preferredScope);
    final sortOrder = _watchlistSortOrderOf(
      context,
      fallback: viewPreferences.sortOrder,
    );
    final filter = _watchlistFilterOf(context);
    final selectedCollection = requestedScope.collectionId == null
        ? null
        : collections
              .where((entry) => entry.id == requestedScope.collectionId)
              .firstOrNull;
    final scope =
        requestedScope.collectionId != null &&
            collectionsAsync.hasValue &&
            selectedCollection == null
        ? const WatchlistScope.all()
        : requestedScope;
    if (scope.isAll &&
        requestedScope.collectionId != null &&
        !_hasExplicitCollectionQuery(context) &&
        preferredScope.collectionId != null) {
      unawaited(viewPreferences.setScope(const WatchlistScope.all()));
    }
    final items = scope.isAll
        ? allItems
        : ref.watch(watchlistItemsForScopeProvider(scope));
    final quotes = scope.isAll
        ? ref.watch(watchlistQuoteSnapshotsProvider)
        : ref.watch(watchlistQuoteSnapshotsForScopeProvider(scope));
    final collectionCounts = WatchlistCollectionCounts.from(
      items: allItems.value ?? const <WatchlistItem>[],
      members: membersAsync.value ?? const <WatchlistCollectionMember>[],
    );

    ref.listen(
      scope.isAll
          ? watchlistQuoteSnapshotsProvider
          : watchlistQuoteSnapshotsForScopeProvider(scope),
      (_, next) {
        next.whenData((snapshots) => _notifyAlerts(context, snapshots));
      },
    );

    return AppPageScaffold(
      title: l10n.watchlistTitle,
      actions: [
        AppHeaderAction(
          icon: const Icon(FLucideIcons.refreshCw),
          semanticsLabel: l10n.commonRefresh,
          onPress: () {
            ref.invalidate(watchlistQuoteSnapshotsProvider);
            ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
          },
        ),
        if (selectedCollection != null)
          AppHeaderAction(
            icon: const Icon(FLucideIcons.folderCog),
            semanticsLabel: l10n.watchlistEditCollectionAction,
            onPress: () => _editCollection(selectedCollection),
          ),
        AppHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.watchlistAddAction,
          onPress: () => showWatchlistItemSheet(
            context: context,
            initialCollectionId: scope.collectionId,
          ),
        ),
      ],
      childPad: false,
      child: items.whenOrError(
        context: context,
        data: (items) => _WatchlistBody(
          items: items,
          collections: collections,
          selectedCollection: selectedCollection,
          collectionCounts: collectionCounts,
          scope: scope,
          sortOrder: sortOrder,
          filter: filter,
          snapshots: quotes.value ?? const [],
          loadingQuotes: quotes.isLoading,
          onScopeSelected: (next) => unawaited(_selectScope(next)),
          onSortSelected: (next) => unawaited(_selectSortOrder(next)),
          onFilter: () => _showFilter(filter),
          onClearFilter: () =>
              _replaceWatchlistFilter(context, const WatchlistFilter()),
          onCreateCollection: _createCollection,
          onBulkManage: items.isEmpty || collections.isEmpty
              ? null
              : () => showWatchlistBulkMembershipSheet(
                  context: context,
                  items: items,
                  collections: collections,
                  removalCollectionId: scope.collectionId,
                ),
          onReorderCollections: collections.length < 2
              ? null
              : () => _reorderCollections(collections),
          onReorderItems:
              scope.collectionId == null ||
                  items.length < 2 ||
                  sortOrder != WatchlistSortOrder.defaultOrder
              ? null
              : () => _reorderItems(scope.collectionId!, items),
          onAdd: () => showWatchlistItemSheet(
            context: context,
            initialCollectionId: scope.collectionId,
          ),
          onEdit: (item) =>
              showWatchlistItemSheet(context: context, item: item),
          onManageCollections: (item) =>
              showWatchlistMembershipSheet(context: context, item: item),
          onRemoveFromCollection: scope.collectionId == null
              ? null
              : (item) => _removeFromCollection(
                  item,
                  scope.collectionId!,
                  membersAsync.value ?? const <WatchlistCollectionMember>[],
                ),
          onRemove: (item) => _removeItem(item),
        ),
        error: (error, _) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, error),
          retryLabel: l10n.commonRetry,
          onRetry: () {
            ref.invalidate(watchlistItemsProvider);
            ref.invalidate(watchlistQuoteSnapshotsProvider);
            ref.invalidate(watchlistCollectionsProvider);
            ref.invalidate(watchlistCollectionMembersProvider);
            ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
          },
        ),
      ),
    );
  }

  void _notifyAlerts(
    BuildContext context,
    List<WatchlistQuoteSnapshot> snapshots,
  ) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    for (final snapshot in snapshots) {
      final quote = snapshot.quote;
      final rules = snapshot.item.alertRules;
      if (quote == null || !rules.enabled || !rules.hasRule) continue;
      final price = quote.price;
      final above = rules.above;
      if (above != null && price >= above) {
        _showOnce(
          context,
          '${snapshot.item.id}:above:${above.toString()}',
          l10n.watchlistAlertTriggeredAbove(
            snapshot.item.displaySymbol,
            price.toString(),
          ),
        );
      }
      final below = rules.below;
      if (below != null && price <= below) {
        _showOnce(
          context,
          '${snapshot.item.id}:below:${below.toString()}',
          l10n.watchlistAlertTriggeredBelow(
            snapshot.item.displaySymbol,
            price.toString(),
          ),
        );
      }
    }
  }

  void _showOnce(BuildContext context, String signature, String message) {
    if (!_alertSignatures.add(signature)) return;
    AppMessenger.show(context, ToastKind.warning, message);
  }

  Future<void> _removeItem(WatchlistItem item) async {
    final l10n = AppLocalizations.of(context);
    final repo = await ref.read(watchlistRepositoryProvider.future);
    final collectionIds = await repo.remove(item);
    ref.invalidate(watchlistQuoteSnapshotsProvider);
    ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
    if (!mounted) return;
    final undo = FormUndoAction(() async {
      await repo.add(
        symbol: item.symbol,
        market: item.market,
        rules: item.alertRules,
        collectionIds: collectionIds,
      );
      ref.invalidate(watchlistQuoteSnapshotsProvider);
      ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
    });
    AppMessenger.show(
      context,
      ToastKind.success,
      l10n.commonDeleted,
      actionLabel: l10n.commonUndo,
      onAction: () => unawaited(
        runFormUndoWithFeedback(
          context: context,
          action: undo,
          logger: ref.read(loggerProvider),
          successMessage: l10n.commonUndoSucceeded,
          failureMessage: (_) => l10n.commonUndoFailed,
          retryLabel: l10n.commonRetry,
          tag: 'watchlist-remove',
        ),
      ),
    );
  }

  Future<void> _createCollection() async {
    await showWatchlistCollectionSheet(context: context);
  }

  Future<void> _editCollection(WatchlistCollection collection) async {
    final deleted = await showWatchlistCollectionSheet(
      context: context,
      collection: collection,
    );
    if (deleted == true && mounted) {
      _replaceWatchlistScope(context, const WatchlistScope.all());
    }
  }

  Future<void> _reorderCollections(
    List<WatchlistCollection> collections,
  ) async {
    await showWatchlistOrderSheet<WatchlistCollection>(
      context: context,
      title: AppLocalizations.of(context).watchlistReorderCollectionsAction,
      entries: collections,
      idOf: (entry) => entry.id,
      labelOf: (entry) => entry.name,
      onSave: (ordered) async {
        final repo = await ref.read(watchlistRepositoryProvider.future);
        await repo.reorderCollections(ordered);
      },
    );
  }

  Future<void> _selectScope(WatchlistScope scope) async {
    await ref.read(watchlistViewPreferencesProvider).setScope(scope);
    if (!mounted) return;
    _replaceWatchlistScope(context, scope);
  }

  Future<void> _selectSortOrder(WatchlistSortOrder order) async {
    await ref.read(watchlistViewPreferencesProvider).setSortOrder(order);
    if (!mounted) return;
    _replaceWatchlistSortOrder(context, order);
  }

  Future<void> _showFilter(WatchlistFilter current) async {
    final next = await showWatchlistFilterSheet(
      context: context,
      initial: current,
    );
    if (next == null || !mounted) return;
    _replaceWatchlistFilter(context, next);
  }

  Future<void> _reorderItems(
    String collectionId,
    List<WatchlistItem> items,
  ) async {
    await showWatchlistOrderSheet<WatchlistItem>(
      context: context,
      title: AppLocalizations.of(context).watchlistReorderSymbolsAction,
      entries: items,
      idOf: (entry) => entry.id,
      labelOf: (entry) => entry.displaySymbol,
      onSave: (ordered) async {
        final repo = await ref.read(watchlistRepositoryProvider.future);
        await repo.reorderItemsInCollection(
          collectionId: collectionId,
          orderedItems: ordered,
        );
      },
    );
  }

  Future<void> _removeFromCollection(
    WatchlistItem item,
    String collectionId,
    List<WatchlistCollectionMember> members,
  ) async {
    final previousIds = members
        .where((entry) => entry.watchlistItemId == item.id)
        .map((entry) => entry.collectionId)
        .toSet();
    final remainingIds = Set<String>.from(previousIds)..remove(collectionId);
    final repo = await ref.read(watchlistRepositoryProvider.future);
    await repo.setCollectionsForItem(item: item, collectionIds: remainingIds);
    ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final undo = FormUndoAction(() async {
      await repo.setCollectionsForItem(item: item, collectionIds: previousIds);
      ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
    });
    AppMessenger.show(
      context,
      ToastKind.success,
      l10n.watchlistRemovedFromCollection,
      actionLabel: l10n.commonUndo,
      onAction: () => unawaited(
        runFormUndoWithFeedback(
          context: context,
          action: undo,
          logger: ref.read(loggerProvider),
          successMessage: l10n.commonUndoSucceeded,
          failureMessage: (_) => l10n.commonUndoFailed,
          retryLabel: l10n.commonRetry,
          tag: 'watchlist-remove-from-collection',
        ),
      ),
    );
  }
}

class _WatchlistBody extends StatelessWidget {
  const _WatchlistBody({
    required this.items,
    required this.collections,
    required this.selectedCollection,
    required this.collectionCounts,
    required this.scope,
    required this.sortOrder,
    required this.filter,
    required this.snapshots,
    required this.loadingQuotes,
    required this.onScopeSelected,
    required this.onSortSelected,
    required this.onFilter,
    required this.onClearFilter,
    required this.onCreateCollection,
    required this.onBulkManage,
    required this.onReorderCollections,
    required this.onReorderItems,
    required this.onAdd,
    required this.onEdit,
    required this.onManageCollections,
    required this.onRemoveFromCollection,
    required this.onRemove,
  });

  final List<WatchlistItem> items;
  final List<WatchlistCollection> collections;
  final WatchlistCollection? selectedCollection;
  final WatchlistCollectionCounts collectionCounts;
  final WatchlistScope scope;
  final WatchlistSortOrder sortOrder;
  final WatchlistFilter filter;
  final List<WatchlistQuoteSnapshot> snapshots;
  final bool loadingQuotes;
  final ValueChanged<WatchlistScope> onScopeSelected;
  final ValueChanged<WatchlistSortOrder> onSortSelected;
  final VoidCallback onFilter;
  final VoidCallback onClearFilter;
  final VoidCallback onCreateCollection;
  final VoidCallback? onBulkManage;
  final VoidCallback? onReorderCollections;
  final VoidCallback? onReorderItems;
  final VoidCallback onAdd;
  final ValueChanged<WatchlistItem> onEdit;
  final ValueChanged<WatchlistItem> onManageCollections;
  final ValueChanged<WatchlistItem>? onRemoveFromCollection;
  final ValueChanged<WatchlistItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final snapshot in snapshots) snapshot.item.id: snapshot};
    final filteredItems = filterWatchlistItems(
      items: items,
      snapshots: snapshots,
      filter: filter,
    );
    final filteredItemIds = filteredItems.map((item) => item.id).toSet();
    final filteredSnapshots = snapshots
        .where((snapshot) => filteredItemIds.contains(snapshot.item.id))
        .toList(growable: false);
    final summary = WatchlistQuoteSummary.fromSnapshots(
      symbolCount: filteredItems.length,
      snapshots: filteredSnapshots,
    );
    final analysis = analyzeWatchlistItems(
      items: filteredItems,
      snapshots: filteredSnapshots,
    );
    final sortedItems = sortWatchlistItems(
      items: filteredItems,
      snapshots: filteredSnapshots,
      order: sortOrder,
    );
    Widget list({ValueChanged<String>? onSelect}) => AdaptiveContentFrame(
      maxWidth: AdaptiveMaxWidth.narrow,
      expandSinglePrimary: true,
      primary: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellTabContentPadding(
          context,
          left: AppSpacing.s0,
          top: AppSpacing.s0,
          right: AppSpacing.s0,
          bottom: AppSpacing.s16,
        ),
        children: [
          _WatchlistCollectionBar(
            collections: collections,
            counts: collectionCounts,
            scope: scope,
            sortOrder: sortOrder,
            filter: filter,
            onSelected: onScopeSelected,
            onSortSelected: onSortSelected,
            onFilter: onFilter,
            onCreate: onCreateCollection,
            onBulkManage: onBulkManage,
            onReorderCollections: onReorderCollections,
            onReorderItems: onReorderItems,
          ),
          const SizedBox(height: AppSpacing.s8),
          if (items.isEmpty)
            _WatchlistEmpty(onAdd: onAdd)
          else if (filteredItems.isEmpty)
            _WatchlistFilteredEmpty(onClear: onClearFilter)
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
              child: _WatchlistSummary(
                summary: summary,
                loadingQuotes: loadingQuotes,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
              child: _WatchlistAnalysisCard(
                analysis: analysis,
                loadingQuotes: loadingQuotes,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            AppGroupedSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < sortedItems.length; i++) ...[
                    _WatchlistRow(
                      item: sortedItems[i],
                      snapshot: byId[sortedItems[i].id],
                      loadingQuote:
                          loadingQuotes && byId[sortedItems[i].id] == null,
                      onEdit: () => onEdit(sortedItems[i]),
                      onManageCollections: () =>
                          onManageCollections(sortedItems[i]),
                      onRemoveFromCollection: onRemoveFromCollection == null
                          ? null
                          : () => onRemoveFromCollection!(sortedItems[i]),
                      onRemove: () => onRemove(sortedItems[i]),
                      onSelect: onSelect == null
                          ? null
                          : () => onSelect(sortedItems[i].id),
                    ),
                    if (i != sortedItems.length - 1)
                      const AppGroupedDivider(
                        indent: AppSpacing.s12,
                        endIndent: AppSpacing.s12,
                      ),
                  ],
                ],
              ),
            ),
            if (selectedCollection != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
                child: WatchlistSimulationSection(
                  collection: selectedCollection!,
                  items: items,
                  snapshots: snapshots,
                ),
              ),
            ],
          ],
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (GoRouter.maybeOf(context) == null ||
            !MasterDetailLayout.shouldUseMasterDetail(constraints.maxWidth) ||
            sortedItems.isEmpty) {
          return list();
        }
        final selectedId = selectedQueryOf(context);
        final selectedItem = sortedItems
            .where((item) => item.id == selectedId)
            .firstOrNull;
        return MasterDetailLayout(
          master: list(
            onSelect: (id) => replaceSelectedQuery(
              context,
              path: FinanceRoutes.wealthWatchlist,
              selected: id,
            ),
          ),
          detail: selectedItem == null
              ? MasterDetailEmpty(
                  message: AppLocalizations.of(context).watchlistSelectItem,
                  icon: FLucideIcons.bellRing,
                )
              : _WatchlistDetail(
                  item: selectedItem,
                  snapshot: byId[selectedItem.id],
                  loadingQuote: loadingQuotes && byId[selectedItem.id] == null,
                  onEdit: () => onEdit(selectedItem),
                  onManageCollections: () => onManageCollections(selectedItem),
                  onRemoveFromCollection: onRemoveFromCollection == null
                      ? null
                      : () => onRemoveFromCollection!(selectedItem),
                  onRemove: () => onRemove(selectedItem),
                ),
        );
      },
    );
  }
}

class _WatchlistSummary extends StatelessWidget {
  const _WatchlistSummary({required this.summary, required this.loadingQuotes});

  final WatchlistQuoteSummary summary;
  final bool loadingQuotes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final waitingForFirstSnapshot =
        loadingQuotes && summary.availableQuoteCount == 0;
    final pendingValue = waitingForFirstSnapshot ? '…' : null;
    return AppGroupedSurface(
      key: const ValueKey<String>('watchlist-quote-summary'),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: AppMetricCluster(
        dense: true,
        items: [
          AppMetricItem(
            label: l10n.watchlistSummarySymbols,
            value: '${summary.symbolCount}',
          ),
          AppMetricItem(
            label: l10n.watchlistSummaryQuotes,
            value:
                pendingValue ??
                '${summary.availableQuoteCount} / ${summary.symbolCount}',
          ),
          AppMetricItem(
            label: l10n.watchlistSummaryAdvancing,
            value: pendingValue ?? '${summary.advancingCount}',
          ),
          AppMetricItem(
            label: l10n.watchlistSummaryDeclining,
            value: pendingValue ?? '${summary.decliningCount}',
          ),
        ],
      ),
    );
  }
}

class _WatchlistAnalysisCard extends StatelessWidget {
  const _WatchlistAnalysisCard({
    required this.analysis,
    required this.loadingQuotes,
  });

  final WatchlistCollectionAnalysis analysis;
  final bool loadingQuotes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final overall = analysis.overall;
    final pending = loadingQuotes && overall.availableQuoteCount == 0;
    final median = overall.medianChangePercent;
    return AppGroupedSurface(
      key: const ValueKey<String>('watchlist-collection-analysis'),
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.watchlistAnalysisTitle, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s4),
          Text(
            l10n.watchlistAnalysisMarketTimingNote,
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          AppMetricCluster(
            dense: true,
            items: [
              AppMetricItem(
                label: l10n.watchlistAnalysisCoverage,
                value: pending
                    ? '…'
                    : formatters.percent(
                        overall.quoteCoverageRatio,
                        decimalDigits: 0,
                      ),
              ),
              AppMetricItem(
                label: l10n.watchlistAnalysisMedianChange,
                value: pending
                    ? '…'
                    : median == null
                    ? '—'
                    : formatters.signedPercent(
                        median.toDouble(),
                        decimalDigits: 2,
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          AppMetricCluster(
            dense: true,
            items: [
              AppMetricItem(
                label: l10n.watchlistAnalysisAlertCoverage,
                value: l10n.watchlistAnalysisCoverageValue(
                  overall.alertConfiguredCount,
                  overall.symbolCount,
                ),
              ),
              AppMetricItem(
                label: l10n.watchlistAnalysisTriggeredAlerts,
                value: pending ? '…' : '${overall.triggeredAlertCount}',
              ),
            ],
          ),
          if (!pending) ...[
            const SizedBox(height: AppSpacing.s12),
            const AppDivider(horizontalPadding: 0),
            const SizedBox(height: AppSpacing.s10),
            Text(
              l10n.watchlistAnalysisFreshnessSummary(
                overall.liveQuoteCount,
                overall.cachedQuoteCount,
                overall.staleQuoteCount,
                overall.unavailableQuoteCount,
              ),
              style: context.captionStyle,
            ),
            if (overall.topGainer case final mover?) ...[
              const SizedBox(height: AppSpacing.s6),
              Text(
                l10n.watchlistAnalysisTopGainer(
                  mover.symbol,
                  formatters.signedPercent(
                    mover.changePercent.toDouble(),
                    decimalDigits: 2,
                  ),
                ),
                style: context.captionStyle,
              ),
            ],
            if (overall.topDecliner case final mover?) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(
                l10n.watchlistAnalysisTopDecliner(
                  mover.symbol,
                  formatters.signedPercent(
                    mover.changePercent.toDouble(),
                    decimalDigits: 2,
                  ),
                ),
                style: context.captionStyle,
              ),
            ],
            if (analysis.byMarket.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s12),
              Text(
                l10n.watchlistAnalysisMarketsTitle,
                style: context.labelStyle,
              ),
              const SizedBox(height: AppSpacing.s6),
              for (final market in analysis.byMarket) ...[
                Text(
                  l10n.watchlistAnalysisMarketSummary(
                    _marketLabel(l10n, market.market!),
                    market.availableQuoteCount,
                    market.symbolCount,
                    market.advancingCount,
                    market.decliningCount,
                    market.unchangedCount,
                    market.unknownPreviousCloseCount,
                  ),
                  style: context.captionStyle,
                ),
                if (market != analysis.byMarket.last)
                  const SizedBox(height: AppSpacing.s4),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

class _WatchlistCollectionBar extends StatelessWidget {
  const _WatchlistCollectionBar({
    required this.collections,
    required this.counts,
    required this.scope,
    required this.sortOrder,
    required this.filter,
    required this.onSelected,
    required this.onSortSelected,
    required this.onFilter,
    required this.onCreate,
    required this.onBulkManage,
    required this.onReorderCollections,
    required this.onReorderItems,
  });

  final List<WatchlistCollection> collections;
  final WatchlistCollectionCounts counts;
  final WatchlistScope scope;
  final WatchlistSortOrder sortOrder;
  final WatchlistFilter filter;
  final ValueChanged<WatchlistScope> onSelected;
  final ValueChanged<WatchlistSortOrder> onSortSelected;
  final VoidCallback onFilter;
  final VoidCallback onCreate;
  final VoidCallback? onBulkManage;
  final VoidCallback? onReorderCollections;
  final VoidCallback? onReorderItems;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        AppSpacing.s8,
        AppSpacing.s12,
        AppSpacing.s4,
      ),
      child: Row(
        children: [
          AppFilterChip(
            label: l10n.watchlistCollectionCountLabel(
              l10n.watchlistAllCollection,
              counts.all,
            ),
            active: scope.isAll,
            onPress: () => onSelected(const WatchlistScope.all()),
          ),
          const SizedBox(width: AppSpacing.s8),
          AppFilterChip(
            label: l10n.watchlistCollectionCountLabel(
              l10n.watchlistUngroupedCollection,
              counts.ungrouped,
            ),
            active: scope.ungrouped,
            onPress: () => onSelected(const WatchlistScope.ungrouped()),
          ),
          for (final collection in collections) ...[
            const SizedBox(width: AppSpacing.s8),
            AppFilterChip(
              label: l10n.watchlistCollectionCountLabel(
                collection.name,
                counts.forCollection(collection.id),
              ),
              active: scope.collectionId == collection.id,
              onPress: () =>
                  onSelected(WatchlistScope.collection(collection.id)),
            ),
          ],
          const SizedBox(width: AppSpacing.s8),
          AppIconButton(
            icon: FLucideIcons.folderPlus,
            tooltip: l10n.watchlistCreateCollectionAction,
            onPress: onCreate,
            size: appActionTargetSize(context),
            iconSize: AppIconSizes.sm,
            surface: AppIconButtonSurface.softMuted,
          ),
          const SizedBox(width: AppSpacing.s8),
          _WatchlistSortMenu(value: sortOrder, onChanged: onSortSelected),
          const SizedBox(width: AppSpacing.s8),
          AppIconButton(
            key: const ValueKey<String>('watchlist-filter-trigger'),
            icon: filter.isDefault
                ? FLucideIcons.listFilter
                : FLucideIcons.listFilterPlus,
            tooltip: l10n.watchlistFilterAction,
            onPress: onFilter,
            size: appActionTargetSize(context),
            iconSize: AppIconSizes.sm,
            surface: AppIconButtonSurface.softMuted,
          ),
          if (onBulkManage != null) ...[
            const SizedBox(width: AppSpacing.s8),
            AppIconButton(
              key: const ValueKey<String>('watchlist-bulk-manage-trigger'),
              icon: FLucideIcons.listChecks,
              tooltip: l10n.watchlistBulkManageAction,
              onPress: onBulkManage,
              size: appActionTargetSize(context),
              iconSize: AppIconSizes.sm,
              surface: AppIconButtonSurface.softMuted,
            ),
          ],
          if (onReorderCollections != null) ...[
            const SizedBox(width: AppSpacing.s8),
            AppIconButton(
              key: const ValueKey<String>('watchlist-reorder-collections'),
              icon: FLucideIcons.listRestart,
              tooltip: l10n.watchlistReorderCollectionsAction,
              onPress: onReorderCollections,
              size: appActionTargetSize(context),
              iconSize: AppIconSizes.sm,
              surface: AppIconButtonSurface.softMuted,
            ),
          ],
          if (onReorderItems != null) ...[
            const SizedBox(width: AppSpacing.s8),
            AppIconButton(
              key: const ValueKey<String>('watchlist-reorder-symbols'),
              icon: FLucideIcons.gripVertical,
              tooltip: l10n.watchlistReorderSymbolsAction,
              onPress: onReorderItems,
              size: appActionTargetSize(context),
              iconSize: AppIconSizes.sm,
              surface: AppIconButtonSurface.softMuted,
            ),
          ],
        ],
      ),
    );
  }
}

class _WatchlistSortMenu extends StatelessWidget {
  const _WatchlistSortMenu({required this.value, required this.onChanged});

  final WatchlistSortOrder value;
  final ValueChanged<WatchlistSortOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppAdaptiveSelectionMenu<WatchlistSortOrder>(
      title: l10n.watchlistSortAction,
      value: value,
      onChanged: onChanged,
      options: [
        AppAdaptiveSelection<WatchlistSortOrder>(
          value: WatchlistSortOrder.defaultOrder,
          title: l10n.watchlistSortDefault,
          icon: FLucideIcons.clock3,
        ),
        AppAdaptiveSelection<WatchlistSortOrder>(
          value: WatchlistSortOrder.gainers,
          title: l10n.watchlistSortGainers,
          icon: FLucideIcons.trendingUp,
        ),
        AppAdaptiveSelection<WatchlistSortOrder>(
          value: WatchlistSortOrder.decliners,
          title: l10n.watchlistSortDecliners,
          icon: FLucideIcons.trendingDown,
        ),
        AppAdaptiveSelection<WatchlistSortOrder>(
          value: WatchlistSortOrder.symbol,
          title: l10n.watchlistSortSymbol,
          icon: FLucideIcons.arrowDownAZ,
        ),
      ],
      triggerBuilder: (context, openMenu, focusNode) => Focus(
        focusNode: focusNode,
        child: AppIconButton(
          key: const ValueKey<String>('watchlist-sort-trigger'),
          icon: FLucideIcons.arrowUpDown,
          tooltip: l10n.watchlistSortAction,
          onPress: openMenu,
          size: appActionTargetSize(context),
          iconSize: AppIconSizes.sm,
          surface: AppIconButtonSurface.softMuted,
        ),
      ),
    );
  }
}

class _WatchlistEmpty extends StatelessWidget {
  const _WatchlistEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.bellRing,
      title: l10n.watchlistEmptyTitle,
      message: l10n.watchlistEmptyBody,
      action: FButton(onPress: onAdd, child: Text(l10n.watchlistAddAction)),
    );
  }
}

class _WatchlistFilteredEmpty extends StatelessWidget {
  const _WatchlistFilteredEmpty({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: FLucideIcons.funnelX,
      title: l10n.watchlistFilterEmptyTitle,
      message: l10n.watchlistFilterEmptyBody,
      action: FButton(
        variant: FButtonVariant.outline,
        onPress: onClear,
        child: Text(l10n.watchlistFilterClearAction),
      ),
    );
  }
}

class _WatchlistRow extends StatelessWidget {
  const _WatchlistRow({
    required this.item,
    required this.snapshot,
    required this.loadingQuote,
    required this.onEdit,
    required this.onManageCollections,
    required this.onRemoveFromCollection,
    required this.onRemove,
    this.onSelect,
  });

  final WatchlistItem item;
  final WatchlistQuoteSnapshot? snapshot;
  final bool loadingQuote;
  final VoidCallback onEdit;
  final VoidCallback onManageCollections;
  final VoidCallback? onRemoveFromCollection;
  final VoidCallback onRemove;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final quote = snapshot?.quote;
    final actionsTitle = l10n.watchlistRowActionsTitle(item.displaySymbol);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.foreground.withValues(
                    alpha: AppOpacity.whisper,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _marketIcon(item.market),
                  size: AppIconSizes.md,
                  color: colors.mutedForeground,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: AppTappable(
                  onPress: onSelect,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.displaySymbol, style: context.labelStyle),
                        Text(
                          _marketLabel(l10n, item.market),
                          style: context.captionStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (loadingQuote)
                const SizedBox(
                  width: AppIconSizes.h18,
                  height: AppIconSizes.h18,
                  child: FCircularProgress(),
                )
              else if (quote == null)
                Text(
                  l10n.watchlistPriceUnavailable,
                  style: context.theme.typography.body.lg,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MoneyText(
                      amount: quote.price.toDouble(),
                      currencyCode: quote.currency,
                      style: context.theme.typography.body.lg,
                    ),
                    if (quote.changePercent case final changePercent?) ...[
                      const SizedBox(height: AppSpacing.s2),
                      DeltaText.percentFromRatio(
                        key: ValueKey<String>(
                          'watchlist-row-change-${item.id}',
                        ),
                        ratio: changePercent.toDouble(),
                        style: TypographyTokens.numericCaptionStrong,
                      ),
                    ],
                  ],
                ),
              const SizedBox(width: AppSpacing.s4),
              AppAdaptiveActionMenu(
                title: actionsTitle,
                actions: <AppAdaptiveAction>[
                  AppAdaptiveAction(
                    icon: FLucideIcons.layers,
                    title: l10n.watchlistManageCollectionsAction,
                    onPress: onManageCollections,
                  ),
                  AppAdaptiveAction(
                    icon: FLucideIcons.bell,
                    title: l10n.watchlistEditAlertsAction,
                    onPress: onEdit,
                  ),
                  if (onRemoveFromCollection != null)
                    AppAdaptiveAction(
                      icon: FLucideIcons.folderMinus,
                      title: l10n.watchlistRemoveFromCollectionAction,
                      onPress: onRemoveFromCollection!,
                    ),
                  AppAdaptiveAction(
                    icon: FLucideIcons.trash2,
                    title: l10n.watchlistRemoveAction,
                    destructive: true,
                    onPress: onRemove,
                  ),
                ],
                triggerBuilder: (context, openMenu, focusNode) => Focus(
                  focusNode: focusNode,
                  child: AppIconButton(
                    icon: FLucideIcons.ellipsisVertical,
                    tooltip: actionsTitle,
                    onPress: openMenu,
                    size: appActionTargetSize(context),
                    iconSize: AppIconSizes.sm,
                    surface: AppIconButtonSurface.softMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              _FreshnessChip(snapshot: snapshot),
              if (item.alertRules.above != null)
                _RuleChip(
                  label: l10n.watchlistAlertAboveChip(
                    item.alertRules.above.toString(),
                  ),
                ),
              if (item.alertRules.below != null)
                _RuleChip(
                  label: l10n.watchlistAlertBelowChip(
                    item.alertRules.below.toString(),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WatchlistDetail extends StatelessWidget {
  const _WatchlistDetail({
    required this.item,
    required this.snapshot,
    required this.loadingQuote,
    required this.onEdit,
    required this.onManageCollections,
    required this.onRemoveFromCollection,
    required this.onRemove,
  });

  final WatchlistItem item;
  final WatchlistQuoteSnapshot? snapshot;
  final bool loadingQuote;
  final VoidCallback onEdit;
  final VoidCallback onManageCollections;
  final VoidCallback? onRemoveFromCollection;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quote = snapshot?.quote;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s24),
      children: [
        Text(item.displaySymbol, style: context.theme.typography.body.xl),
        const SizedBox(height: AppSpacing.s4),
        Text(_marketLabel(l10n, item.market), style: context.captionStyle),
        const SizedBox(height: AppSpacing.s24),
        if (loadingQuote)
          const Align(
            alignment: Alignment.centerLeft,
            child: FCircularProgress(),
          )
        else if (quote == null)
          Text(
            l10n.watchlistPriceUnavailable,
            style: context.theme.typography.body.md,
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(
                amount: quote.price.toDouble(),
                currencyCode: quote.currency,
                style: context.theme.typography.body.xl,
              ),
              if (quote.changePercent case final changePercent?) ...[
                const SizedBox(width: AppSpacing.s12),
                DeltaChip(
                  key: ValueKey<String>('watchlist-detail-change-${item.id}'),
                  value: changePercent.toDouble() * 100,
                  fractionDigits: 2,
                ),
              ],
            ],
          ),
        const SizedBox(height: AppSpacing.s16),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            _FreshnessChip(snapshot: snapshot),
            if (item.alertRules.above case final above?)
              _RuleChip(label: l10n.watchlistAlertAboveChip(above.toString())),
            if (item.alertRules.below case final below?)
              _RuleChip(label: l10n.watchlistAlertBelowChip(below.toString())),
          ],
        ),
        const SizedBox(height: AppSpacing.s24),
        FButton(
          variant: FButtonVariant.outline,
          onPress: onManageCollections,
          prefix: const Icon(FLucideIcons.layers),
          child: Text(l10n.watchlistManageCollectionsAction),
        ),
        const SizedBox(height: AppSpacing.s8),
        FButton(
          onPress: onEdit,
          prefix: const Icon(FLucideIcons.bell),
          child: Text(l10n.watchlistEditAlertsAction),
        ),
        if (onRemoveFromCollection != null) ...[
          const SizedBox(height: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.outline,
            onPress: onRemoveFromCollection,
            prefix: const Icon(FLucideIcons.folderMinus),
            child: Text(l10n.watchlistRemoveFromCollectionAction),
          ),
        ],
        const SizedBox(height: AppSpacing.s8),
        FButton(
          variant: FButtonVariant.ghost,
          onPress: onRemove,
          prefix: const Icon(FLucideIcons.trash2),
          child: Text(l10n.watchlistRemoveAction),
        ),
      ],
    );
  }
}

class _FreshnessChip extends StatelessWidget {
  const _FreshnessChip({required this.snapshot});

  final WatchlistQuoteSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = switch (snapshot?.response?.freshness) {
      DataFreshness.live => l10n.watchlistFreshnessLive,
      DataFreshness.cachedFresh => l10n.watchlistFreshnessCache,
      DataFreshness.stale => l10n.watchlistFreshnessStale,
      null => l10n.watchlistFreshnessStale,
    };
    return _RuleChip(label: label);
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.foreground.withValues(
          alpha: AppOpacity.whisper,
        ),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s10,
          vertical: AppSpacing.s6,
        ),
        child: Text(label, style: context.theme.typography.body.xs),
      ),
    );
  }
}

Future<void> showWatchlistItemSheet({
  required BuildContext context,
  WatchlistItem? item,
  String? initialCollectionId,
}) async {
  final l10n = AppLocalizations.of(context);
  final dirty = FormDirtyController();
  try {
    await showAppSheet<void>(
      context: context,
      title: item == null
          ? l10n.watchlistAddTitle
          : l10n.watchlistEditAlertTitle(item.displaySymbol),
      maxHeightFactor: 0.9,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) => _WatchlistItemSheet(
        dirty: dirty,
        item: item,
        initialCollectionId: initialCollectionId,
      ),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistItemSheet extends ConsumerStatefulWidget {
  const _WatchlistItemSheet({
    required this.dirty,
    required this.item,
    required this.initialCollectionId,
  });

  final FormDirtyController dirty;
  final WatchlistItem? item;
  final String? initialCollectionId;

  @override
  ConsumerState<_WatchlistItemSheet> createState() =>
      _WatchlistItemSheetState();
}

class _WatchlistItemSheetState extends ConsumerState<_WatchlistItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _above;
  late final TextEditingController _below;
  late final Set<String> _selectedCollectionIds;
  LocalSecurityChoice? _choice;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _above = TextEditingController(text: item?.alertRules.above?.toString());
    _below = TextEditingController(text: item?.alertRules.below?.toString());
    _selectedCollectionIds = <String>{?widget.initialCollectionId};
    widget.dirty.bindTextControllers([_above, _below]);
    widget.dirty.snapshotBaseline();
  }

  @override
  void dispose() {
    _above.dispose();
    _below.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final collections = widget.item == null
        ? ref.watch(watchlistCollectionsProvider)
        : null;
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.item == null) ...[
            SymbolField(
              markets: _editableMarkets,
              onChanged: (choice) {
                setState(() => _choice = choice);
                widget.dirty.markDirty();
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            AppSheetSectionLabel(l10n.watchlistAddToCollectionsField),
            if (collections!.isLoading)
              const Align(
                alignment: Alignment.centerLeft,
                child: FCircularProgress(),
              )
            else if (collections.hasError)
              FButton(
                variant: FButtonVariant.outline,
                onPress: () => ref.invalidate(watchlistCollectionsProvider),
                child: Text(l10n.commonRetry),
              )
            else if ((collections.value ?? const <WatchlistCollection>[])
                .isEmpty)
              Text(l10n.watchlistNoCollectionsBody, style: context.captionStyle)
            else
              AppGroupedSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (
                      var index = 0;
                      index < collections.value!.length;
                      index++
                    ) ...[
                      _WatchlistCollectionCheckboxRow(
                        key: ValueKey<String>(
                          'watchlist-add-collection-${collections.value![index].id}',
                        ),
                        collection: collections.value![index],
                        selected: _selectedCollectionIds.contains(
                          collections.value![index].id,
                        ),
                        onToggle: () =>
                            _toggleCollection(collections.value![index].id),
                      ),
                      if (index != collections.value!.length - 1)
                        const AppGroupedDivider(
                          indent: AppSpacing.s12,
                          endIndent: AppSpacing.s12,
                        ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.s12),
          ],
          FTextFormField(
            control: FTextFieldControl.managed(controller: _above),
            label: Text(l10n.watchlistAlertAboveField),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            validator: _validateDecimal,
          ),
          const SizedBox(height: AppSpacing.s12),
          FTextFormField(
            control: FTextFieldControl.managed(controller: _below),
            label: Text(l10n.watchlistAlertBelowField),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            validator: _validateDecimal,
          ),
          const SizedBox(height: AppSpacing.s20),
          AppSheetFooter(
            cancelLabel: l10n.commonCancel,
            submitLabel: widget.item == null
                ? l10n.watchlistAddAction
                : l10n.watchlistSaveAlertsAction,
            busy: _saving,
            onSubmit: _save,
          ),
        ],
      ),
    );
  }

  String? _validateDecimal(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = Decimal.tryParse(raw);
    if (parsed == null || parsed <= Decimal.zero) {
      return AppLocalizations.of(context).watchlistInvalidNumber;
    }
    return null;
  }

  void _toggleCollection(String collectionId) {
    setState(() {
      if (!_selectedCollectionIds.add(collectionId)) {
        _selectedCollectionIds.remove(collectionId);
      }
      widget.dirty.markDirty();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final item = widget.item;
    final choice = _choice;
    if (item == null && choice == null) return; // add path requires a pick
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(watchlistRepositoryProvider.future);
      final rules = PriceAlertRules(
        above: Decimal.tryParse(_above.text.trim()),
        below: Decimal.tryParse(_below.text.trim()),
      );
      if (item == null) {
        await repo.add(
          symbol: choice!.symbol,
          market: choice.market,
          rules: rules,
          collectionIds: _selectedCollectionIds,
        );
      } else {
        await repo.updateAlertRules(item: item, rules: rules);
      }
      ref.invalidate(watchlistQuoteSnapshotsProvider);
      ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.dirty.busy = false;
    }
  }
}

Future<bool?> showWatchlistCollectionSheet({
  required BuildContext context,
  WatchlistCollection? collection,
}) async {
  final dirty = FormDirtyController();
  try {
    return await showAppSheet<bool>(
      context: context,
      title: collection == null
          ? AppLocalizations.of(context).watchlistCreateCollectionAction
          : AppLocalizations.of(context).watchlistEditCollectionAction,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) =>
          _WatchlistCollectionSheet(dirty: dirty, collection: collection),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistCollectionSheet extends ConsumerStatefulWidget {
  const _WatchlistCollectionSheet({
    required this.dirty,
    required this.collection,
  });

  final FormDirtyController dirty;
  final WatchlistCollection? collection;

  @override
  ConsumerState<_WatchlistCollectionSheet> createState() =>
      _WatchlistCollectionSheetState();
}

class _WatchlistCollectionSheetState
    extends ConsumerState<_WatchlistCollectionSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.collection?.name);
    widget.dirty.bindTextControllers([_name]);
    widget.dirty.snapshotBaseline();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTextFormField(
            autofocus: true,
            control: FTextFieldControl.managed(controller: _name),
            label: Text(l10n.watchlistCollectionNameField),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? l10n.watchlistCollectionNameRequired
                : null,
          ),
          if (widget.collection != null) ...[
            const SizedBox(height: AppSpacing.s12),
            FButton(
              variant: FButtonVariant.destructive,
              onPress: _saving ? null : _delete,
              prefix: const Icon(FLucideIcons.trash2),
              child: Text(l10n.watchlistDeleteCollectionAction),
            ),
          ],
          const SizedBox(height: AppSpacing.s20),
          AppSheetFooter(
            cancelLabel: l10n.commonCancel,
            submitLabel: l10n.commonSave,
            busy: _saving,
            onSubmit: _save,
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(watchlistRepositoryProvider.future);
      final collection = widget.collection;
      if (collection == null) {
        await repo.createCollection(_name.text);
      } else {
        await repo.renameCollection(collection: collection, name: _name.text);
      }
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(false);
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.dirty.busy = false;
    }
  }

  Future<void> _delete() async {
    final collection = widget.collection!;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.watchlistDeleteCollectionTitle(collection.name)),
      body: Text(l10n.watchlistDeleteCollectionBody),
      confirmLabel: l10n.watchlistDeleteCollectionAction,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      final repo = await ref.read(watchlistRepositoryProvider.future);
      await repo.deleteCollection(collection);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.dirty.busy = false;
    }
  }
}

Future<WatchlistFilter?> showWatchlistFilterSheet({
  required BuildContext context,
  required WatchlistFilter initial,
}) => showAppSheet<WatchlistFilter>(
  context: context,
  title: AppLocalizations.of(context).watchlistFilterAction,
  builder: (_) => _WatchlistFilterSheet(initial: initial),
);

class _WatchlistFilterSheet extends StatefulWidget {
  const _WatchlistFilterSheet({required this.initial});

  final WatchlistFilter initial;

  @override
  State<_WatchlistFilterSheet> createState() => _WatchlistFilterSheetState();
}

class _WatchlistFilterSheetState extends State<_WatchlistFilterSheet> {
  late AssetMarket? _market;
  late WatchlistAlertFilter _alerts;
  late WatchlistFreshnessFilter _freshness;

  @override
  void initState() {
    super.initState();
    _market = widget.initial.market;
    _alerts = widget.initial.alerts;
    _freshness = widget.initial.freshness;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSheetSectionLabel(l10n.watchlistFilterMarketSection),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            AppFilterChip(
              label: l10n.watchlistFilterAllOption,
              active: _market == null,
              onPress: () => setState(() => _market = null),
            ),
            for (final market in _editableMarkets)
              AppFilterChip(
                label: _marketLabel(l10n, market),
                active: _market == market,
                onPress: () => setState(() => _market = market),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        AppSheetSectionLabel(l10n.watchlistFilterAlertsSection),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            for (final option in WatchlistAlertFilter.values)
              AppFilterChip(
                label: switch (option) {
                  WatchlistAlertFilter.all => l10n.watchlistFilterAllOption,
                  WatchlistAlertFilter.configured =>
                    l10n.watchlistFilterAlertsConfigured,
                  WatchlistAlertFilter.none => l10n.watchlistFilterAlertsNone,
                },
                active: _alerts == option,
                onPress: () => setState(() => _alerts = option),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        AppSheetSectionLabel(l10n.watchlistFilterFreshnessSection),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s8,
          children: [
            for (final option in WatchlistFreshnessFilter.values)
              AppFilterChip(
                label: switch (option) {
                  WatchlistFreshnessFilter.all => l10n.watchlistFilterAllOption,
                  WatchlistFreshnessFilter.live => l10n.watchlistFreshnessLive,
                  WatchlistFreshnessFilter.cached =>
                    l10n.watchlistFreshnessCache,
                  WatchlistFreshnessFilter.stale =>
                    l10n.watchlistFreshnessStale,
                  WatchlistFreshnessFilter.unavailable =>
                    l10n.watchlistPriceUnavailable,
                },
                active: _freshness == option,
                onPress: () => setState(() => _freshness = option),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s16),
        FButton(
          variant: FButtonVariant.outline,
          onPress: _reset,
          child: Text(l10n.watchlistFilterClearAction),
        ),
        const SizedBox(height: AppSpacing.s20),
        AppSheetFooter(
          cancelLabel: l10n.commonCancel,
          submitLabel: l10n.watchlistFilterApplyAction,
          onSubmit: () => Navigator.of(context).pop(
            WatchlistFilter(
              market: _market,
              alerts: _alerts,
              freshness: _freshness,
            ),
          ),
        ),
      ],
    );
  }

  void _reset() {
    setState(() {
      _market = null;
      _alerts = WatchlistAlertFilter.all;
      _freshness = WatchlistFreshnessFilter.all;
    });
  }
}

Future<void> showWatchlistOrderSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> entries,
  required String Function(T entry) idOf,
  required String Function(T entry) labelOf,
  required Future<void> Function(List<T> ordered) onSave,
}) async {
  final dirty = FormDirtyController();
  try {
    await showAppSheet<void>(
      context: context,
      title: title,
      maxHeightFactor: 0.9,
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) => _WatchlistOrderSheet<T>(
        entries: entries,
        idOf: idOf,
        labelOf: labelOf,
        onSave: onSave,
        dirty: dirty,
      ),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistOrderSheet<T> extends StatefulWidget {
  const _WatchlistOrderSheet({
    required this.entries,
    required this.idOf,
    required this.labelOf,
    required this.onSave,
    required this.dirty,
  });

  final List<T> entries;
  final String Function(T entry) idOf;
  final String Function(T entry) labelOf;
  final Future<void> Function(List<T> ordered) onSave;
  final FormDirtyController dirty;

  @override
  State<_WatchlistOrderSheet<T>> createState() =>
      _WatchlistOrderSheetState<T>();
}

class _WatchlistOrderSheetState<T> extends State<_WatchlistOrderSheet<T>> {
  late final List<T> _entries;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _entries = List<T>.of(widget.entries);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          itemCount: _entries.length,
          onReorderItem: _reorder,
          itemBuilder: (context, index) {
            final entry = _entries[index];
            return Padding(
              key: ValueKey<String>(widget.idOf(entry)),
              padding: EdgeInsets.only(
                bottom: index == _entries.length - 1 ? 0 : AppSpacing.s8,
              ),
              child: AppGroupedSurface(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.labelOf(entry),
                          style: context.labelStyle,
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(AppSpacing.s8),
                          child: Icon(
                            FLucideIcons.gripVertical,
                            size: AppIconSizes.sm,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.s20),
        AppSheetFooter(
          cancelLabel: l10n.commonCancel,
          submitLabel: l10n.commonSave,
          busy: _saving,
          enabled: widget.dirty.isDirty,
          onSubmit: _save,
        ),
      ],
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final entry = _entries.removeAt(oldIndex);
      _entries.insert(newIndex, entry);
      widget.dirty.markDirty();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    widget.dirty.busy = true;
    try {
      await widget.onSave(List<T>.unmodifiable(_entries));
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
      widget.dirty.busy = false;
    }
  }
}

Future<void> showWatchlistBulkMembershipSheet({
  required BuildContext context,
  required List<WatchlistItem> items,
  required List<WatchlistCollection> collections,
  String? removalCollectionId,
}) => showAppSheet<void>(
  context: context,
  title: AppLocalizations.of(context).watchlistBulkManageAction,
  maxHeightFactor: 0.9,
  builder: (_) => _WatchlistBulkMembershipSheet(
    items: items,
    collections: collections,
    removalCollectionId: removalCollectionId,
  ),
);

class _WatchlistBulkMembershipSheet extends ConsumerStatefulWidget {
  const _WatchlistBulkMembershipSheet({
    required this.items,
    required this.collections,
    required this.removalCollectionId,
  });

  final List<WatchlistItem> items;
  final List<WatchlistCollection> collections;
  final String? removalCollectionId;

  @override
  ConsumerState<_WatchlistBulkMembershipSheet> createState() =>
      _WatchlistBulkMembershipSheetState();
}

class _WatchlistBulkMembershipSheetState
    extends ConsumerState<_WatchlistBulkMembershipSheet> {
  final Set<String> _selectedItemIds = <String>{};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allSelected = _selectedItemIds.length == widget.items.length;
    final removing = widget.removalCollectionId != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.watchlistBulkSelectedCount(_selectedItemIds.length),
          style: context.captionStyle,
        ),
        const SizedBox(height: AppSpacing.s8),
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _WatchlistBulkSelectRow(
                key: const ValueKey<String>('watchlist-bulk-select-all'),
                title: l10n.watchlistBulkSelectAll,
                selected: allSelected,
                enabled: !_saving,
                onToggle: _toggleAll,
              ),
              const AppGroupedDivider(
                indent: AppSpacing.s12,
                endIndent: AppSpacing.s12,
              ),
              for (var index = 0; index < widget.items.length; index++) ...[
                _WatchlistBulkSelectRow(
                  key: ValueKey<String>(
                    'watchlist-bulk-item-${widget.items[index].id}',
                  ),
                  title: widget.items[index].displaySymbol,
                  subtitle: _marketLabel(l10n, widget.items[index].market),
                  selected: _selectedItemIds.contains(widget.items[index].id),
                  enabled: !_saving,
                  onToggle: () => _toggleItem(widget.items[index].id),
                ),
                if (index != widget.items.length - 1)
                  const AppGroupedDivider(
                    indent: AppSpacing.s12,
                    endIndent: AppSpacing.s12,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s20),
        AppSheetFooter(
          cancelLabel: l10n.commonCancel,
          submitLabel: removing
              ? l10n.watchlistBulkRemoveAction
              : l10n.watchlistBulkAddAction,
          enabled: _selectedItemIds.isNotEmpty,
          busy: _saving,
          onSubmit: _apply,
        ),
      ],
    );
  }

  void _toggleAll() {
    setState(() {
      if (_selectedItemIds.length == widget.items.length) {
        _selectedItemIds.clear();
      } else {
        _selectedItemIds
          ..clear()
          ..addAll(widget.items.map((item) => item.id));
      }
    });
  }

  void _toggleItem(String itemId) {
    setState(() {
      if (!_selectedItemIds.add(itemId)) _selectedItemIds.remove(itemId);
    });
  }

  Future<void> _apply() async {
    final removalCollectionId = widget.removalCollectionId;
    final targetCollectionId = removalCollectionId ?? await _chooseCollection();
    if (targetCollectionId == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final selectedItems = widget.items
          .where((item) => _selectedItemIds.contains(item.id))
          .toList(growable: false);
      final repo = await ref.read(watchlistRepositoryProvider.future);
      if (removalCollectionId == null) {
        await repo.addItemsToCollection(
          items: selectedItems,
          collectionId: targetCollectionId,
        );
      } else {
        await repo.removeItemsFromCollection(
          items: selectedItems,
          collectionId: targetCollectionId,
        );
      }
      ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.success,
        AppLocalizations.of(context).watchlistBulkUpdated(selectedItems.length),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _chooseCollection() => showAppSheet<String>(
    context: context,
    title: AppLocalizations.of(context).watchlistBulkChooseCollectionTitle,
    builder: (sheetContext) => AppGroupedSurface(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < widget.collections.length; index++) ...[
            AppTappable(
              key: ValueKey<String>(
                'watchlist-bulk-target-${widget.collections[index].id}',
              ),
              onPress: () =>
                  Navigator.of(sheetContext).pop(widget.collections[index].id),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s12),
                child: Row(
                  children: [
                    const Icon(FLucideIcons.layers, size: AppIconSizes.sm),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      child: Text(
                        widget.collections[index].name,
                        style: context.labelStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (index != widget.collections.length - 1)
              const AppGroupedDivider(
                indent: AppSpacing.s12,
                endIndent: AppSpacing.s12,
              ),
          ],
        ],
      ),
    ),
  );
}

class _WatchlistBulkSelectRow extends StatelessWidget {
  const _WatchlistBulkSelectRow({
    super.key,
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onToggle,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AppTappable(
      onPress: enabled ? onToggle : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s10,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: context.labelStyle),
                  if (subtitle case final subtitle?)
                    Text(subtitle, style: context.captionStyle),
                ],
              ),
            ),
            FCheckbox(
              value: selected,
              onChange: enabled ? (_) => onToggle() : null,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showWatchlistMembershipSheet({
  required BuildContext context,
  required WatchlistItem item,
}) async {
  final dirty = FormDirtyController();
  try {
    await showAppSheet<void>(
      context: context,
      title: AppLocalizations.of(context)
          .watchlistManageCollectionsTitle(item.displaySymbol),
      dirtyGuard: dirty,
      confirmDismiss: () => confirmDiscardIfDirty(context, dirty),
      builder: (_) => _WatchlistMembershipSheet(item: item, dirty: dirty),
    );
  } finally {
    dirty.dispose();
  }
}

class _WatchlistCollectionCheckboxRow extends StatelessWidget {
  const _WatchlistCollectionCheckboxRow({
    super.key,
    required this.collection,
    required this.selected,
    required this.onToggle,
    this.enabled = true,
  });

  final WatchlistCollection collection;
  final bool selected;
  final VoidCallback onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppTappable(
      onPress: enabled ? onToggle : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s8,
        ),
        child: Row(
          children: [
            Expanded(child: Text(collection.name, style: context.labelStyle)),
            FCheckbox(
              value: selected,
              onChange: enabled ? (_) => onToggle() : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _WatchlistMembershipSheet extends ConsumerStatefulWidget {
  const _WatchlistMembershipSheet({required this.item, required this.dirty});

  final WatchlistItem item;
  final FormDirtyController dirty;

  @override
  ConsumerState<_WatchlistMembershipSheet> createState() =>
      _WatchlistMembershipSheetState();
}

class _WatchlistMembershipSheetState
    extends ConsumerState<_WatchlistMembershipSheet> {
  Set<String>? _selected;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final collections = ref.watch(watchlistCollectionsProvider);
    final members = ref.watch(watchlistCollectionMembersProvider);
    if (collections.isLoading || members.isLoading) {
      return const Center(child: FCircularProgress());
    }
    if (collections.hasError || members.hasError) {
      return AppEmptyState.error(
        title: l10n.commonLoadFailed,
        retryLabel: l10n.commonRetry,
        onRetry: () {
          ref.invalidate(watchlistCollectionsProvider);
          ref.invalidate(watchlistCollectionMembersProvider);
        },
      );
    }
    final available = collections.value ?? const <WatchlistCollection>[];
    final current = (members.value ?? const <WatchlistCollectionMember>[])
        .where((entry) => entry.watchlistItemId == widget.item.id)
        .map((entry) => entry.collectionId)
        .toSet();
    final selected = _selected ??= current;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (available.isEmpty)
          AppEmptyState(
            icon: FLucideIcons.layers,
            title: l10n.watchlistNoCollectionsBody,
            action: FButton(
              variant: FButtonVariant.outline,
              onPress: _saving ? null : _createCollection,
              child: Text(l10n.watchlistCreateCollectionAction),
            ),
          )
        else
          for (final collection in available)
            _WatchlistCollectionCheckboxRow(
              collection: collection,
              selected: selected.contains(collection.id),
              enabled: !_saving,
              onToggle: () => _toggle(collection.id),
            ),
        const SizedBox(height: AppSpacing.s20),
        AppSheetFooter(
          cancelLabel: l10n.commonCancel,
          submitLabel: l10n.watchlistSaveCollectionsAction,
          busy: _saving,
          onSubmit: _save,
        ),
      ],
    );
  }

  void _toggle(String collectionId) {
    setState(() {
      final selected = _selected ?? <String>{};
      if (!selected.add(collectionId)) selected.remove(collectionId);
      _selected = selected;
      widget.dirty.markDirty();
    });
  }

  Future<void> _createCollection() async {
    final name = await showAppTextPromptSheet(
      context: context,
      title: AppLocalizations.of(context).watchlistCreateCollectionAction,
      fieldLabel: AppLocalizations.of(context).watchlistCollectionNameField,
      submitLabel: AppLocalizations.of(context).commonSave,
      cancelLabel: AppLocalizations.of(context).commonCancel,
      validator: (value) => value.trim().isEmpty
          ? AppLocalizations.of(context).watchlistCollectionNameRequired
          : null,
    );
    if (name == null || !mounted) return;
    final repo = await ref.read(watchlistRepositoryProvider.future);
    final collection = await repo.createCollection(name);
    setState(() {
      (_selected ??= <String>{}).add(collection.id);
      widget.dirty.markDirty();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = await ref.read(watchlistRepositoryProvider.future);
      await repo.setCollectionsForItem(
        item: widget.item,
        collectionIds: Set<String>.from(_selected ?? const <String>{}),
      );
      ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
      widget.dirty.markPristine();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

WatchlistScope _watchlistScopeOf(
  BuildContext context, {
  required WatchlistScope fallback,
}) {
  if (GoRouter.maybeOf(context) == null) return fallback;
  final raw = GoRouterState.of(context)
      .uri
      .queryParameters[_collectionQueryKey];
  if (raw == null) return fallback;
  if (raw.isEmpty) return const WatchlistScope.all();
  if (raw == _ungroupedQueryValue) return const WatchlistScope.ungrouped();
  return WatchlistScope.collection(raw);
}

bool _hasExplicitCollectionQuery(BuildContext context) {
  if (GoRouter.maybeOf(context) == null) return false;
  return GoRouterState.of(context).uri.queryParameters
      .containsKey(_collectionQueryKey);
}

WatchlistSortOrder _watchlistSortOrderOf(
  BuildContext context, {
  required WatchlistSortOrder fallback,
}) {
  if (GoRouter.maybeOf(context) == null) return fallback;
  final query = GoRouterState.of(context).uri.queryParameters;
  if (!query.containsKey(_sortQueryKey)) return fallback;
  return switch (query[_sortQueryKey]) {
    _gainersSortQueryValue => WatchlistSortOrder.gainers,
    _declinersSortQueryValue => WatchlistSortOrder.decliners,
    _symbolSortQueryValue => WatchlistSortOrder.symbol,
    _ => WatchlistSortOrder.defaultOrder,
  };
}

WatchlistFilter _watchlistFilterOf(BuildContext context) {
  if (GoRouter.maybeOf(context) == null) return const WatchlistFilter();
  final query = GoRouterState.of(context).uri.queryParameters;
  final market = assetMarketFromWire(query[_marketFilterQueryKey] ?? '');
  final alerts = switch (query[_alertFilterQueryKey]) {
    'configured' => WatchlistAlertFilter.configured,
    'none' => WatchlistAlertFilter.none,
    _ => WatchlistAlertFilter.all,
  };
  final freshness = switch (query[_freshnessFilterQueryKey]) {
    'live' => WatchlistFreshnessFilter.live,
    'cached' => WatchlistFreshnessFilter.cached,
    'stale' => WatchlistFreshnessFilter.stale,
    'unavailable' => WatchlistFreshnessFilter.unavailable,
    _ => WatchlistFreshnessFilter.all,
  };
  return WatchlistFilter(
    market: market == AssetMarket.unknown ? null : market,
    alerts: alerts,
    freshness: freshness,
  );
}

void _replaceWatchlistScope(BuildContext context, WatchlistScope scope) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  final current = router.routeInformationProvider.value.uri;
  final query = <String, String>{...current.queryParameters}
    ..remove(kSelectedQueryKey);
  if (scope.isAll) {
    query.remove(_collectionQueryKey);
  } else {
    query[_collectionQueryKey] = scope.ungrouped
        ? _ungroupedQueryValue
        : scope.collectionId!;
  }
  router.go(
    Uri(
      path: FinanceRoutes.wealthWatchlist,
      queryParameters: query.isEmpty ? null : query,
    ).toString(),
  );
}

void _replaceWatchlistSortOrder(
  BuildContext context,
  WatchlistSortOrder order,
) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  final current = router.routeInformationProvider.value.uri;
  final query = <String, String>{...current.queryParameters};
  final queryValue = switch (order) {
    WatchlistSortOrder.defaultOrder => null,
    WatchlistSortOrder.gainers => _gainersSortQueryValue,
    WatchlistSortOrder.decliners => _declinersSortQueryValue,
    WatchlistSortOrder.symbol => _symbolSortQueryValue,
  };
  if (queryValue == null) {
    query.remove(_sortQueryKey);
  } else {
    query[_sortQueryKey] = queryValue;
  }
  router.go(
    Uri(
      path: FinanceRoutes.wealthWatchlist,
      queryParameters: query.isEmpty ? null : query,
    ).toString(),
  );
}

void _replaceWatchlistFilter(BuildContext context, WatchlistFilter filter) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  final current = router.routeInformationProvider.value.uri;
  final query = <String, String>{...current.queryParameters};
  if (filter.market == null) {
    query.remove(_marketFilterQueryKey);
  } else {
    query[_marketFilterQueryKey] = filter.market!.wire;
  }
  switch (filter.alerts) {
    case WatchlistAlertFilter.all:
      query.remove(_alertFilterQueryKey);
    case WatchlistAlertFilter.configured:
      query[_alertFilterQueryKey] = 'configured';
    case WatchlistAlertFilter.none:
      query[_alertFilterQueryKey] = 'none';
  }
  switch (filter.freshness) {
    case WatchlistFreshnessFilter.all:
      query.remove(_freshnessFilterQueryKey);
    case WatchlistFreshnessFilter.live:
      query[_freshnessFilterQueryKey] = 'live';
    case WatchlistFreshnessFilter.cached:
      query[_freshnessFilterQueryKey] = 'cached';
    case WatchlistFreshnessFilter.stale:
      query[_freshnessFilterQueryKey] = 'stale';
    case WatchlistFreshnessFilter.unavailable:
      query[_freshnessFilterQueryKey] = 'unavailable';
  }
  router.go(
    Uri(
      path: FinanceRoutes.wealthWatchlist,
      queryParameters: query.isEmpty ? null : query,
    ).toString(),
  );
}

const _editableMarkets = <AssetMarket>[
  AssetMarket.usStock,
  AssetMarket.hkStock,
  AssetMarket.cnA,
  AssetMarket.crypto,
  AssetMarket.fx,
];

String _marketLabel(AppLocalizations l10n, AssetMarket market) {
  return switch (market) {
    AssetMarket.cnA => l10n.watchlistMarketCnA,
    AssetMarket.hkStock => l10n.watchlistMarketHkStock,
    AssetMarket.usStock => l10n.watchlistMarketUsStock,
    AssetMarket.crypto => l10n.watchlistMarketCrypto,
    AssetMarket.fx => l10n.watchlistMarketFx,
    AssetMarket.unknown => l10n.watchlistMarketUnknown,
  };
}

IconData _marketIcon(AssetMarket market) {
  return switch (market) {
    AssetMarket.crypto => FLucideIcons.bitcoin,
    AssetMarket.fx => FLucideIcons.arrowLeftRight,
    AssetMarket.cnA ||
    AssetMarket.hkStock ||
    AssetMarket.usStock => FLucideIcons.chartLine,
    AssetMarket.unknown => FLucideIcons.trendingUp,
  };
}
