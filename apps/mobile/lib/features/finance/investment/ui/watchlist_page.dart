import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/forms/form_submission.dart';
import 'package:naviwealth/core/logging/providers.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/core/shell/shell_chrome.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/investment/notifications/watchlist_alerts.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_providers.dart';
import '../data/watchlist_repository.dart';
import '../data/watchlist_view_state.dart';
import 'watchlist_labels.dart';
import 'watchlist_rows.dart';
import 'watchlist_sections.dart';
import 'watchlist_sheets.dart';
import 'watchlist_simulation_section.dart';

/// The watchlist page.
///
/// Composition only. Scoping and sorting live in [watchlistViewStateProvider],
/// interaction lives in `watchlist_sheets.dart`, and the list/card/row
/// presentation lives in `watchlist_sections.dart` / `watchlist_rows.dart`.
/// Price alerts are no longer driven from here either: they are delivered
/// session-wide by [watchlistAlertMonitorProvider] while the app is open.
class WatchlistPage extends ConsumerWidget {
  const WatchlistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final viewState = ref.watch(watchlistViewStateProvider);
    final allItemsAsync = ref.watch(watchlistItemsProvider);
    final collectionsAsync = ref.watch(watchlistCollectionsProvider);
    final membersAsync = ref.watch(watchlistCollectionMembersProvider);
    final collections = collectionsAsync.value ?? const <WatchlistCollection>[];
    final selectedCollection = viewState.scope.collectionId == null
        ? null
        : collections
              .where((entry) => entry.id == viewState.scope.collectionId)
              .firstOrNull;
    final scope = viewState.scope;
    final items = scope.isAll
        ? allItemsAsync
        : ref.watch(watchlistItemsForScopeProvider(scope));
    final quotes = scope.isAll
        ? ref.watch(watchlistQuoteSnapshotsProvider)
        : ref.watch(watchlistQuoteSnapshotsForScopeProvider(scope));
    final collectionCounts = WatchlistCollectionCounts.from(
      items: allItemsAsync.value ?? const <WatchlistItem>[],
      members: membersAsync.value ?? const <WatchlistCollectionMember>[],
    );

    // Web / desktop, and users who denied the OS permission, still deserve the
    // alert — they just get it as an in-app message while this page is up.
    ref.listen(watchlistAlertFallbacksProvider, (_, next) {
      next.whenData((event) {
        if (ModalRoute.of(context)?.isCurrent == false) return;
        AppMessenger.show(context, ToastKind.warning, event.message);
        unawaited(ref.read(watchlistAlertMonitorProvider).acknowledge(event));
      });
    });

    return AppPageScaffold(
      title: l10n.watchlistTitle,
      actions: [
        AppHeaderAction(
          icon: const Icon(FLucideIcons.refreshCw),
          semanticsLabel: l10n.commonRefresh,
          onPress: () {
            ref.invalidate(watchlistQuoteSnapshotsProvider);
            ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
            ref.invalidate(watchlistSparklineProvider);
          },
        ),
        if (selectedCollection != null)
          AppHeaderAction(
            icon: const Icon(FLucideIcons.folderCog),
            semanticsLabel: l10n.watchlistEditCollectionAction,
            onPress: () => _editCollection(context, ref, selectedCollection),
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
          viewState: viewState,
          snapshots: quotes.value ?? const [],
          loadingQuotes: quotes.isLoading,
          onScopeSelected: (next) =>
              ref.read(watchlistViewStateProvider.notifier).selectScope(next),
          onSortSelected: (next) => ref
              .read(watchlistViewStateProvider.notifier)
              .selectSortOrder(next),
          onFilterChanged: (next) =>
              ref.read(watchlistViewStateProvider.notifier).selectFilter(next),
          onClearFilter: () =>
              ref.read(watchlistViewStateProvider.notifier).clearFilter(),
          onCreateCollection: () =>
              showWatchlistCollectionSheet(context: context),
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
              : () => _reorderCollections(context, ref, collections),
          onReorderItems:
              scope.collectionId == null ||
                  items.length < 2 ||
                  viewState.sortOrder != WatchlistSortOrder.defaultOrder
              ? null
              : () => _reorderItems(context, ref, scope.collectionId!, items),
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
                  context,
                  ref,
                  item,
                  scope.collectionId!,
                  membersAsync.value ?? const <WatchlistCollectionMember>[],
                ),
          onRemove: (item) => _removeItem(context, ref, item),
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
}

class _WatchlistBody extends StatelessWidget {
  const _WatchlistBody({
    required this.items,
    required this.collections,
    required this.selectedCollection,
    required this.collectionCounts,
    required this.scope,
    required this.viewState,
    required this.snapshots,
    required this.loadingQuotes,
    required this.onScopeSelected,
    required this.onSortSelected,
    required this.onFilterChanged,
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
  final WatchlistViewState viewState;
  final List<WatchlistQuoteSnapshot> snapshots;
  final bool loadingQuotes;
  final ValueChanged<WatchlistScope> onScopeSelected;
  final ValueChanged<WatchlistSortOrder> onSortSelected;
  final ValueChanged<WatchlistFilter> onFilterChanged;
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
      filter: viewState.filter,
    );
    final filteredItemIds = filteredItems.map((item) => item.id).toSet();
    final filteredSnapshots = snapshots
        .where((snapshot) => filteredItemIds.contains(snapshot.item.id))
        .toList(growable: false);
    final analysis = analyzeWatchlistItems(
      items: filteredItems,
      snapshots: filteredSnapshots,
    );
    final sortedItems = sortWatchlistItems(
      items: filteredItems,
      snapshots: filteredSnapshots,
      order: viewState.sortOrder,
    );

    Widget rows({required ValueChanged<WatchlistItem> onOpen}) =>
        AppGroupedSurface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < sortedItems.length; i++) ...[
                WatchlistRow(
                  item: sortedItems[i],
                  snapshot: byId[sortedItems[i].id],
                  loadingQuote:
                      loadingQuotes && byId[sortedItems[i].id] == null,
                  onOpen: () => onOpen(sortedItems[i]),
                  onEdit: () => onEdit(sortedItems[i]),
                  onManageCollections: () =>
                      onManageCollections(sortedItems[i]),
                  onRemoveFromCollection: onRemoveFromCollection == null
                      ? null
                      : () => onRemoveFromCollection!(sortedItems[i]),
                  onRemove: () => onRemove(sortedItems[i]),
                ),
                if (i != sortedItems.length - 1)
                  const AppGroupedDivider(
                    indent: AppSpacing.s12,
                    endIndent: AppSpacing.s12,
                  ),
              ],
            ],
          ),
        );

    Widget list({
      required ValueChanged<WatchlistItem> onOpen,
    }) => AdaptiveContentFrame(
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
          WatchlistToolbar(
            collections: collections,
            counts: collectionCounts,
            scope: scope,
            viewState: viewState,
            onScopeSelected: onScopeSelected,
            onSortSelected: onSortSelected,
            onFilterChanged: onFilterChanged,
            onCreateCollection: onCreateCollection,
            onBulkManage: onBulkManage,
            onReorderCollections: onReorderCollections,
            onReorderItems: onReorderItems,
          ),
          const SizedBox(height: AppSpacing.s8),
          if (items.isEmpty)
            WatchlistEmptyState(onAdd: onAdd)
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
              child: WatchlistOverviewCard(
                analysis: analysis,
                loadingQuotes: loadingQuotes,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            if (filteredItems.isEmpty)
              WatchlistFilteredEmptyState(onClear: onClearFilter)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
                child: rows(onOpen: onOpen),
              ),
            // The paper scenario belongs to the collection, so it renders
            // for every selected collection — including one whose symbols
            // are all filtered out, which is when it used to vanish. It
            // stays below the symbols: the watchlist itself is the primary
            // content and keeps the first screen.
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
        final masterDetail =
            GoRouter.maybeOf(context) != null &&
            MasterDetailLayout.shouldUseMasterDetail(constraints.maxWidth) &&
            sortedItems.isNotEmpty;
        if (!masterDetail) {
          return list(
            onOpen: (item) => _openSymbolSheet(context, item, byId[item.id]),
          );
        }
        final selectedId = selectedQueryOf(context);
        final selectedItem = sortedItems
            .where((item) => item.id == selectedId)
            .firstOrNull;
        return MasterDetailLayout(
          master: list(
            onOpen: (item) => replaceSelectedQuery(
              context,
              path: FinanceRoutes.wealthWatchlist,
              selected: item.id,
            ),
          ),
          detail: selectedItem == null
              ? MasterDetailEmpty(
                  message: AppLocalizations.of(context).watchlistSelectItem,
                  icon: FLucideIcons.bellRing,
                )
              : _WatchlistDetailPane(
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

  /// Mobile tap target. Above the breakpoint the detail pane owns this.
  void _openSymbolSheet(
    BuildContext context,
    WatchlistItem item,
    WatchlistQuoteSnapshot? snapshot,
  ) {
    if (GoRouter.maybeOf(context) != null) {
      unawaited(context.push(FinanceRoutes.wealthAsset(item.assetId)));
      return;
    }
    unawaited(
      showWatchlistSymbolSheet(
        context: context,
        item: item,
        snapshot: snapshot,
        loadingQuote: snapshot == null && loadingQuotes,
        onEdit: () => onEdit(item),
        onManageCollections: () => onManageCollections(item),
        onRemoveFromCollection: onRemoveFromCollection == null
            ? null
            : () => onRemoveFromCollection!(item),
        onRemove: () => onRemove(item),
      ),
    );
  }
}

/// Read-only market detail for a watched security that is not an owned asset.
/// Reuses the asset route and watches live providers, including after editing
/// reminder rules. Merely opening this page never creates portfolio data.
class WatchlistAssetDetailPage extends ConsumerWidget {
  const WatchlistAssetDetailPage({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(watchlistItemsProvider);
    return items.when(
      loading: () => ObjectDetailScaffold(
        title: l10n.assetDetailUnknown,
        child: const AssetDetailSkeleton(),
      ),
      error: (error, _) => ObjectDetailScaffold(
        title: l10n.assetDetailUnknown,
        child: AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, error),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(watchlistItemsProvider),
        ),
      ),
      data: (items) {
        final item = items.where((item) => item.assetId == assetId).firstOrNull;
        if (item == null) {
          return ObjectDetailScaffold(
            title: l10n.assetDetailUnknown,
            child: AppEmptyState(
              icon: FLucideIcons.box,
              title: l10n.assetDetailNotFound,
            ),
          );
        }
        final quotes = ref.watch(watchlistQuoteSnapshotsProvider);
        final snapshot = quotes.value
            ?.where((entry) => entry.item.id == item.id)
            .firstOrNull;
        return ObjectDetailScaffold(
          title: l10n.watchlistSymbolDetailTitle(item.displaySymbol),
          actions: [
            AppHeaderAction(
              icon: const Icon(FLucideIcons.refreshCw),
              semanticsLabel: l10n.commonRefresh,
              onPress: () => _invalidateQuotes(ref),
            ),
          ],
          child: SingleChildScrollView(
            child: WatchlistSymbolView(
              item: item,
              snapshot: snapshot,
              loadingQuote: quotes.isLoading && snapshot == null,
              onEdit: () =>
                  showWatchlistItemSheet(context: context, item: item),
              onManageCollections: () =>
                  showWatchlistMembershipSheet(context: context, item: item),
              onRemoveFromCollection: null,
              onRemove: () async {
                await _removeItem(context, ref, item);
                if (context.mounted) smartPop(context);
              },
            ),
          ),
        );
      },
    );
  }
}

/// Desktop detail column: the same view the mobile sheet shows, so the two can
/// never drift apart.
class _WatchlistDetailPane extends StatelessWidget {
  const _WatchlistDetailPane({
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: WatchlistSymbolView(
        item: item,
        snapshot: snapshot,
        loadingQuote: loadingQuote,
        onEdit: onEdit,
        onManageCollections: onManageCollections,
        onRemoveFromCollection: onRemoveFromCollection,
        onRemove: onRemove,
      ),
    );
  }
}

Future<void> _editCollection(
  BuildContext context,
  WidgetRef ref,
  WatchlistCollection collection,
) async {
  final deleted = await showWatchlistCollectionSheet(
    context: context,
    collection: collection,
  );
  if (deleted == true) {
    await ref.read(watchlistViewStateProvider.notifier).forgetScope();
  }
}

Future<void> _reorderCollections(
  BuildContext context,
  WidgetRef ref,
  List<WatchlistCollection> collections,
) {
  return showWatchlistOrderSheet<WatchlistCollection>(
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

Future<void> _reorderItems(
  BuildContext context,
  WidgetRef ref,
  String collectionId,
  List<WatchlistItem> items,
) {
  return showWatchlistOrderSheet<WatchlistItem>(
    context: context,
    title: AppLocalizations.of(context).watchlistReorderSymbolsAction,
    entries: items,
    idOf: (entry) => entry.id,
    labelOf: (entry) => watchlistItemLabel(context, entry),
    onSave: (ordered) async {
      final repo = await ref.read(watchlistRepositoryProvider.future);
      await repo.reorderItemsInCollection(
        collectionId: collectionId,
        orderedItems: ordered,
      );
    },
  );
}

Future<void> _removeItem(
  BuildContext context,
  WidgetRef ref,
  WatchlistItem item,
) async {
  final l10n = AppLocalizations.of(context);
  final repo = await ref.read(watchlistRepositoryProvider.future);
  final collectionIds = await repo.remove(item);
  _invalidateQuotes(ref);
  if (!context.mounted) return;
  final undo = FormUndoAction(() async {
    await repo.add(
      symbol: item.symbol,
      market: item.market,
      rules: item.alertRules,
      collectionIds: collectionIds,
    );
    _invalidateQuotes(ref);
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

Future<void> _removeFromCollection(
  BuildContext context,
  WidgetRef ref,
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
  if (!context.mounted) return;
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

void _invalidateQuotes(WidgetRef ref) {
  ref.invalidate(watchlistQuoteSnapshotsProvider);
  ref.invalidate(watchlistQuoteSnapshotsForScopeProvider);
  ref.invalidate(watchlistSparklineProvider);
}
