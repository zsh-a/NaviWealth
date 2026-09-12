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
    return Row(
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
                  onPress: () => onScopeSelected(const WatchlistScope.all()),
                ),
                for (final entry
                    in <({String label, bool active, WatchlistScope scope})>[
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
                if (!filter.isDefault) ...[
                  const SizedBox(width: AppSpacing.s8),
                  AppFilterChip(
                    key: const ValueKey<String>('watchlist-active-filter-chip'),
                    label: l10n.watchlistFilterActiveChip,
                    active: true,
                    onPress: () => _openFilter(context),
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

/// One card for everything that describes the collection as a whole.
///
/// The page used to render two stacked cards — a four-metric summary and a
/// four-metric analysis — that between them said `Quotes 2/2` and
/// `Quote coverage 100%`, `Advancing 1 / Declining 1` and `1 up · 1 down`, on
/// top of a paragraph of pipeline telemetry ("Live 0 · Cached 1 · Stale 1").
/// They now answer four distinct questions once, and the per-market breakdown
/// folds away until asked for.
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
    return AppGroupedSurface(
      key: WatchlistOverviewCard.cardKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.watchlistOverviewTitle, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s8),
          AppMetricCluster(
            dense: true,
            items: [
              AppMetricItem(
                label: l10n.watchlistSummarySymbols,
                value: '${overall.symbolCount}',
              ),
              AppMetricItem(
                label: l10n.watchlistSummaryQuotes,
                value: pending
                    ? '…'
                    : '${overall.availableQuoteCount} / ${overall.symbolCount}',
              ),
              AppMetricItem(
                label: l10n.watchlistSummaryAdvancingDeclining,
                value: pending
                    ? '…'
                    : '${overall.advancingCount} / ${overall.decliningCount}',
              ),
              AppMetricItem(
                label: l10n.watchlistOverviewTypicalMove,
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
          if (!pending) ...[
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s6,
              runSpacing: AppSpacing.s6,
              children: [
                for (final label in _freshnessLabels(l10n, overall))
                  AppBadge(label: label, size: AppBadgeSize.compact),
                if (_alertSummary(l10n, overall) case final label?)
                  AppBadge(
                    label: label,
                    icon: FLucideIcons.bellRing,
                    size: AppBadgeSize.compact,
                  ),
              ],
            ),
            if (widget.analysis.byMarket.length > 1) ...[
              const SizedBox(height: AppSpacing.s4),
              Semantics(
                button: true,
                expanded: _marketsExpanded,
                child: AppTappable(
                  onPress: () =>
                      setState(() => _marketsExpanded = !_marketsExpanded),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: appActionTargetSize(context),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.watchlistOverviewByMarket,
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
              if (_marketsExpanded)
                Wrap(
                  spacing: AppSpacing.s6,
                  runSpacing: AppSpacing.s6,
                  children: [
                    for (final market in widget.analysis.byMarket)
                      AppBadge(
                        label: _marketLine(l10n, market),
                        size: AppBadgeSize.compact,
                      ),
                  ],
                ),
            ],
          ],
        ],
      ),
    );
  }
}

List<String> _freshnessLabels(
  AppLocalizations l10n,
  WatchlistAnalysisSlice overall,
) {
  final parts = <String>[
    if (overall.liveQuoteCount > 0)
      l10n.watchlistOverviewFreshnessLive(overall.liveQuoteCount),
    if (overall.cachedQuoteCount > 0)
      l10n.watchlistOverviewFreshnessCached(overall.cachedQuoteCount),
    if (overall.staleQuoteCount > 0)
      l10n.watchlistOverviewFreshnessStale(overall.staleQuoteCount),
    if (overall.unavailableQuoteCount > 0)
      l10n.watchlistOverviewFreshnessUnavailable(overall.unavailableQuoteCount),
  ];
  return parts.isEmpty ? [l10n.watchlistOverviewFreshnessNone] : parts;
}

String? _alertSummary(AppLocalizations l10n, WatchlistAnalysisSlice overall) {
  if (overall.alertConfiguredCount == 0) return null;
  return l10n.watchlistOverviewAlertsSummary(
    overall.alertConfiguredCount,
    overall.triggeredAlertCount,
  );
}

String _marketLine(AppLocalizations l10n, WatchlistAnalysisSlice market) =>
    l10n.watchlistOverviewMarketLine(
      watchlistMarketLabel(l10n, market.market ?? AssetMarket.unknown),
      market.advancingCount,
      market.decliningCount,
      market.unchangedCount,
    );

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
