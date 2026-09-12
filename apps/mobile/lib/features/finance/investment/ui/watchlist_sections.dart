import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/investment/domain/watchlist_collection_analysis.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_providers.dart';
import '../data/watchlist_repository.dart';
import '../data/watchlist_view_state.dart';
import 'watchlist_labels.dart';
import 'watchlist_sheets.dart';

/// Scope chips plus one overflow menu.
///
/// The bar used to lay every secondary action out in a single horizontal
/// scroller, which meant the filter button fell outside the viewport on a
/// 390dp phone with no scroll affordance at all. Chips scroll; everything that
/// is not a scope lives behind [FLucideIcons.ellipsis], where it is always
/// reachable and never competes with the scope for width.
class WatchlistToolbar extends StatelessWidget {
  const WatchlistToolbar({
    super.key,
    required this.collections,
    required this.counts,
    required this.scope,
    required this.viewState,
    required this.onScopeSelected,
    required this.onSortSelected,
    required this.onFilterChanged,
    required this.onCreateCollection,
    required this.onBulkManage,
    required this.onReorderCollections,
    required this.onReorderItems,
  });

  final List<WatchlistCollection> collections;
  final WatchlistCollectionCounts counts;
  final WatchlistScope scope;
  final WatchlistViewState viewState;
  final ValueChanged<WatchlistScope> onScopeSelected;
  final ValueChanged<WatchlistSortOrder> onSortSelected;
  final ValueChanged<WatchlistFilter> onFilterChanged;
  final VoidCallback onCreateCollection;
  final VoidCallback? onBulkManage;
  final VoidCallback? onReorderCollections;
  final VoidCallback? onReorderItems;

  static const ValueKey<String> menuTriggerKey = ValueKey<String>(
    'watchlist-more-trigger',
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filter = viewState.filter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s12,
                  AppSpacing.s8,
                  0,
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
                      onPress: () =>
                          onScopeSelected(const WatchlistScope.all()),
                    ),
                    for (final entry
                        in <
                          ({String label, bool active, WatchlistScope scope})
                        >[
                          if (collections.isNotEmpty || scope.ungrouped)
                            (
                              label: l10n.watchlistCollectionCountLabel(
                                l10n.watchlistUngroupedCollection,
                                counts.ungrouped,
                              ),
                              active: scope.ungrouped,
                              scope: const WatchlistScope.ungrouped(),
                            ),
                          for (final collection in collections)
                            (
                              label: l10n.watchlistCollectionCountLabel(
                                collection.name,
                                counts.forCollection(collection.id),
                              ),
                              active: scope.collectionId == collection.id,
                              scope: WatchlistScope.collection(collection.id),
                            ),
                        ]) ...[
                      const SizedBox(width: AppSpacing.s8),
                      AppFilterChip(
                        label: entry.label,
                        active: entry.active,
                        onPress: () => onScopeSelected(entry.scope),
                      ),
                    ],
                    const SizedBox(width: AppSpacing.s12),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.s12),
              child: AppAdaptiveActionMenu(
                title: l10n.watchlistMoreActions,
                actions: <AppAdaptiveAction>[
                  AppAdaptiveAction(
                    icon: FLucideIcons.arrowUpDown,
                    title: l10n.watchlistSortAction,
                    subtitle: _sortLabel(l10n, viewState.sortOrder),
                    onPress: () => _openSort(context),
                  ),
                  AppAdaptiveAction(
                    icon: filter.isDefault
                        ? FLucideIcons.listFilter
                        : FLucideIcons.listFilterPlus,
                    title: l10n.watchlistFilterAction,
                    subtitle: filter.isDefault
                        ? null
                        : l10n.watchlistFilterActiveChip,
                    onPress: () => _openFilter(context),
                  ),
                  AppAdaptiveAction(
                    icon: FLucideIcons.folderPlus,
                    title: l10n.watchlistCreateCollectionAction,
                    onPress: onCreateCollection,
                  ),
                  if (onBulkManage != null)
                    AppAdaptiveAction(
                      icon: FLucideIcons.listChecks,
                      title: l10n.watchlistBulkManageAction,
                      onPress: onBulkManage!,
                    ),
                  if (onReorderCollections != null)
                    AppAdaptiveAction(
                      icon: FLucideIcons.listRestart,
                      title: l10n.watchlistReorderCollectionsAction,
                      onPress: onReorderCollections!,
                    ),
                  if (onReorderItems != null)
                    AppAdaptiveAction(
                      icon: FLucideIcons.gripVertical,
                      title: l10n.watchlistReorderSymbolsAction,
                      onPress: onReorderItems!,
                    ),
                ],
                triggerBuilder: (context, openMenu, focusNode) => Focus(
                  focusNode: focusNode,
                  child: AppIconButton(
                    key: menuTriggerKey,
                    icon: FLucideIcons.ellipsis,
                    tooltip: l10n.watchlistMoreActions,
                    onPress: openMenu,
                    size: appActionTargetSize(context),
                    iconSize: AppIconSizes.sm,
                    surface: AppIconButtonSurface.softMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (viewState.sortOrder != WatchlistSortOrder.defaultOrder ||
            !filter.isDefault)
          Padding(
            key: const ValueKey('watchlist-view-state'),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
            child: Wrap(
              spacing: AppSpacing.s6,
              runSpacing: AppSpacing.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (viewState.sortOrder != WatchlistSortOrder.defaultOrder)
                  AppFilterChip(
                    label: _sortLabel(l10n, viewState.sortOrder),
                    active: true,
                    onPress: () => _openSort(context),
                  ),
                for (final label in _filterLabels(l10n, filter))
                  AppFilterChip(
                    label: label,
                    active: true,
                    onPress: () => _openFilter(context),
                  ),
                if (!filter.isDefault)
                  AppIconButton(
                    key: const ValueKey('watchlist-clear-filter'),
                    icon: FLucideIcons.x,
                    tooltip: l10n.watchlistFilterClearAction,
                    onPress: () => onFilterChanged(const WatchlistFilter()),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _openSort(BuildContext context) async {
    final next = await showWatchlistSortSheet(
      context: context,
      initial: viewState.sortOrder,
    );
    if (next != null) onSortSelected(next);
  }

  Future<void> _openFilter(BuildContext context) async {
    final next = await showWatchlistFilterSheet(
      context: context,
      initial: viewState.filter,
    );
    if (next != null) onFilterChanged(next);
  }
}

String _sortLabel(AppLocalizations l10n, WatchlistSortOrder order) =>
    switch (order) {
      WatchlistSortOrder.defaultOrder => l10n.watchlistSortDefault,
      WatchlistSortOrder.gainers => l10n.watchlistSortGainers,
      WatchlistSortOrder.decliners => l10n.watchlistSortDecliners,
      WatchlistSortOrder.symbol => l10n.watchlistSortSymbol,
    };

/// Daily breadth and exceptional quote states. Secondary statistics unfold
/// on demand, without imposing a full card on a small watchlist.
class WatchlistOverviewCard extends StatefulWidget {
  const WatchlistOverviewCard({
    super.key,
    required this.analysis,
    required this.loadingQuotes,
  });

  final WatchlistCollectionAnalysis analysis;
  final bool loadingQuotes;

  static const ValueKey<String> cardKey = ValueKey<String>(
    'watchlist-overview',
  );

  @override
  State<WatchlistOverviewCard> createState() => _WatchlistOverviewCardState();
}

class _WatchlistOverviewCardState extends State<WatchlistOverviewCard> {
  bool _marketsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final overall = widget.analysis.overall;
    final pending = widget.loadingQuotes && overall.availableQuoteCount == 0;
    final median = overall.medianChangePercent;
    return Column(
      key: WatchlistOverviewCard.cardKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _marketsExpanded,
          child: AppTappable(
            key: const ValueKey('watchlist-overview-expand'),
            onPress: () => setState(() => _marketsExpanded = !_marketsExpanded),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: appActionTargetSize(context),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      pending
                          ? l10n.watchlistOverviewFreshnessNone
                          : l10n.watchlistOverviewMarketLine(
                              l10n.watchlistToday,
                              overall.advancingCount,
                              overall.decliningCount,
                              overall.unchangedCount,
                            ),
                      style: context.captionLabelStyle,
                    ),
                  ),
                  Icon(
                    _marketsExpanded
                        ? FLucideIcons.chevronUp
                        : FLucideIcons.chevronDown,
                    size: AppIconSizes.sm,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (overall.staleQuoteCount > 0 ||
            (!widget.loadingQuotes && overall.unavailableQuoteCount > 0))
          Wrap(
            spacing: AppSpacing.s6,
            runSpacing: AppSpacing.s4,
            children: [
              if (overall.staleQuoteCount > 0)
                AppBadge(
                  label: l10n.watchlistOverviewFreshnessStale(
                    overall.staleQuoteCount,
                  ),
                  tone: AppBadgeTone.warning,
                  size: AppBadgeSize.compact,
                ),
              if (!widget.loadingQuotes && overall.unavailableQuoteCount > 0)
                AppBadge(
                  label: l10n.watchlistOverviewFreshnessUnavailable(
                    overall.unavailableQuoteCount,
                  ),
                  size: AppBadgeSize.compact,
                ),
            ],
          ),
        AnimatedSizeFade(
          visible: _marketsExpanded,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${l10n.watchlistOverviewTypicalMove} · ${median == null ? '—' : formatters.signedPercent(median.toDouble(), decimalDigits: 2)}',
                  style: context.captionStyle,
                ),
                if (overall.alertConfiguredCount > 0)
                  Text(
                    l10n.watchlistOverviewAlertsSummary(
                      overall.alertConfiguredCount,
                      overall.triggeredAlertCount,
                    ),
                    style: context.captionStyle,
                  ),
                if (widget.analysis.byMarket.length > 1) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    l10n.watchlistOverviewByMarket,
                    style: context.captionLabelStyle,
                  ),
                  for (final market in widget.analysis.byMarket)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s4),
                      child: Text(
                        l10n.watchlistOverviewMarketLine(
                          watchlistMarketLabel(
                            l10n,
                            market.market ?? AssetMarket.unknown,
                          ),
                          market.advancingCount,
                          market.decliningCount,
                          market.unchangedCount,
                        ),
                        style: context.captionStyle,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

List<String> _filterLabels(AppLocalizations l10n, WatchlistFilter filter) => [
  if (filter.market case final market?) watchlistMarketLabel(l10n, market),
  if (filter.alerts != WatchlistAlertFilter.all)
    '${l10n.watchlistFilterAlertsSection}: ${filter.alerts == WatchlistAlertFilter.configured ? l10n.watchlistFilterAlertsConfigured : l10n.watchlistFilterAlertsNone}',
  if (filter.freshness != WatchlistFreshnessFilter.all)
    switch (filter.freshness) {
      WatchlistFreshnessFilter.live => l10n.watchlistFreshnessLive,
      WatchlistFreshnessFilter.cached => l10n.watchlistFreshnessCache,
      WatchlistFreshnessFilter.stale => l10n.watchlistFreshnessStale,
      WatchlistFreshnessFilter.unavailable => l10n.watchlistPriceUnavailable,
      WatchlistFreshnessFilter.all => '',
    },
];

class WatchlistEmptyState extends StatelessWidget {
  const WatchlistEmptyState({super.key, required this.onAdd});

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

class WatchlistFilteredEmptyState extends StatelessWidget {
  const WatchlistFilteredEmptyState({super.key, required this.onClear});

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
