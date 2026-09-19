import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Stable scope navigation and directly reachable search, sort and filters.
/// Collection administration stays in the overflow menu.
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
    this.onEditCollection,
    this.onOpenSimulation,
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
  final VoidCallback? onEditCollection;
  final VoidCallback? onOpenSimulation;

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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FButton(
                    key: const ValueKey('watchlist-scope-trigger'),
                    mainAxisSize: MainAxisSize.min,
                    variant: FButtonVariant.ghost,
                    suffix: const Icon(
                      FLucideIcons.chevronDown,
                      size: AppIconSizes.sm,
                    ),
                    onPress: () => showAppSheet<void>(
                      context: context,
                      title: l10n.watchlistManageScope,
                      builder: (_) => _WatchlistCollectionPicker(
                        collections: collections,
                        counts: counts,
                        scope: scope,
                        onSelected: onScopeSelected,
                      ),
                    ),
                    child: Flexible(
                      child: Text(
                        scope.isAll
                            ? l10n.watchlistAllCollection
                            : scope.ungrouped
                            ? l10n.watchlistUngroupedCollection
                            : collections
                                      .where((c) => c.id == scope.collectionId)
                                      .firstOrNull
                                      ?.name ??
                                  l10n.watchlistAllCollection,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
              if (onOpenSimulation != null) ...[
                const SizedBox(width: AppSpacing.s8),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: onOpenSimulation,
                  child: Text(l10n.watchlistSimulationOpenAction),
                ),
              ],
              AppAdaptiveActionMenu(
                title: l10n.watchlistMoreActions,
                actions: <AppAdaptiveAction>[
                  if (onEditCollection != null)
                    AppAdaptiveAction(
                      icon: FLucideIcons.folderCog,
                      title: l10n.watchlistEditCollectionAction,
                      onPress: onEditCollection!,
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s12,
            AppSpacing.s4,
            AppSpacing.s12,
            AppSpacing.s8,
          ),
          child: Row(
            children: [
              const Expanded(child: _WatchlistSearch()),
              const SizedBox(width: AppSpacing.s8),
              AppIconButton(
                key: const ValueKey('watchlist-sort-trigger'),
                icon: FLucideIcons.arrowUpDown,
                tooltip:
                    '${l10n.watchlistSortAction} · ${_sortLabel(l10n, viewState.sortOrder)}',
                onPress: () => _openSort(context),
              ),
              AppIconButton(
                key: const ValueKey('watchlist-filter-trigger'),
                icon: filter.isDefault
                    ? FLucideIcons.listFilter
                    : FLucideIcons.listFilterPlus,
                tooltip: l10n.watchlistFilterAction,
                onPress: () => _openFilter(context),
              ),
            ],
          ),
        ),
        if (viewState.sortOrder != WatchlistSortOrder.defaultOrder ||
            !filter.isDefault)
          Padding(
            key: const ValueKey('watchlist-view-state'),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
                      onClear: () =>
                          onSortSelected(WatchlistSortOrder.defaultOrder),
                      clearSemanticLabel: l10n.watchlistSortDefault,
                    ),
                  for (final label in _filterLabels(l10n, filter))
                    AppFilterChip(
                      label: label,
                      active: true,
                      onPress: () => _openFilter(context),
                      onClear: () {
                        final labels = _filterLabels(l10n, filter);
                        final index = labels.indexOf(label);
                        final marketIndex = filter.market == null ? -1 : 0;
                        final alertIndex =
                            filter.alerts == WatchlistAlertFilter.all
                            ? -1
                            : (filter.market == null ? 0 : 1);
                        onFilterChanged(
                          WatchlistFilter(
                            market: index == marketIndex ? null : filter.market,
                            alerts: index == alertIndex
                                ? WatchlistAlertFilter.all
                                : filter.alerts,
                            freshness:
                                index != marketIndex && index != alertIndex
                                ? WatchlistFreshnessFilter.all
                                : filter.freshness,
                          ),
                        );
                      },
                      clearSemanticLabel:
                          '${l10n.watchlistFilterClearAction}: $label',
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

class _WatchlistSearch extends ConsumerStatefulWidget {
  const _WatchlistSearch();
  @override
  ConsumerState<_WatchlistSearch> createState() => _WatchlistSearchState();
}

class _WatchlistSearchState extends ConsumerState<_WatchlistSearch> {
  late final TextEditingController _controller = TextEditingController(
    text: ref.read(watchlistViewStateProvider).query,
  );
  final _focus = FocusNode();
  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(
      watchlistViewStateProvider.select((state) => state.query),
    );
    if (_controller.text != query) _controller.text = query;
    final l10n = AppLocalizations.of(context);
    return AppSearchField(
      controller: _controller,
      focusNode: _focus,
      hint: l10n.watchlistSearchHint,
      clearLabel: l10n.aiChatSessionsSearchClear,
      onChanged: ref.read(watchlistViewStateProvider.notifier).search,
    );
  }
}

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
                Text(
                  l10n.watchlistOverviewFreshnessStale(overall.staleQuoteCount),
                  style: context.captionStyle,
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

class _WatchlistCollectionPicker extends StatefulWidget {
  const _WatchlistCollectionPicker({
    required this.collections,
    required this.counts,
    required this.scope,
    required this.onSelected,
  });
  final List<WatchlistCollection> collections;
  final WatchlistCollectionCounts counts;
  final WatchlistScope scope;
  final ValueChanged<WatchlistScope> onSelected;
  @override
  State<_WatchlistCollectionPicker> createState() =>
      _WatchlistCollectionPickerState();
}

class _WatchlistCollectionPickerState
    extends State<_WatchlistCollectionPicker> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options =
        <(WatchlistScope, String, int)>[
              (
                const WatchlistScope.all(),
                l10n.watchlistAllCollection,
                widget.counts.all,
              ),
              (
                const WatchlistScope.ungrouped(),
                l10n.watchlistUngroupedCollection,
                widget.counts.ungrouped,
              ),
              for (final collection in widget.collections)
                (
                  WatchlistScope.collection(collection.id),
                  collection.name,
                  widget.counts.forCollection(collection.id),
                ),
            ]
            .where(
              (entry) => entry.$2.toLowerCase().contains(
                _search.text.trim().toLowerCase(),
              ),
            )
            .toList();
    return SizedBox(
      height: AppControlHeights.searchSheet,
      child: Column(
        children: [
          AppSearchField(
            controller: _search,
            hint: l10n.watchlistManageScope,
            clearLabel: l10n.aiChatSessionsSearchClear,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.s8),
          Expanded(
            child: ListView.builder(
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                return AppActionSheetTile(
                  icon: option.$1 == widget.scope
                      ? FLucideIcons.check
                      : FLucideIcons.layers,
                  title: l10n.watchlistCollectionCountLabel(
                    option.$2,
                    option.$3,
                  ),
                  onPress: () {
                    Navigator.of(context).pop();
                    widget.onSelected(option.$1);
                  },
                );
              },
            ),
          ),
        ],
      ),
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
