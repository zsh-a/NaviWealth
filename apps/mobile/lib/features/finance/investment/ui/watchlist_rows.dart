import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_providers.dart';
import '../data/watchlist_repository.dart';
import 'watchlist_labels.dart';

/// Stable quote grid: identity/price, then name/trend/daily change.
class WatchlistRow extends StatelessWidget {
  const WatchlistRow({
    super.key,
    required this.item,
    required this.snapshot,
    required this.loadingQuote,
    required this.onOpen,
    required this.onEdit,
    required this.onManageCollections,
    required this.onRemoveFromCollection,
    required this.onRemove,
    this.selected = false,
  });
  final WatchlistItem item;
  final WatchlistQuoteSnapshot? snapshot;
  final bool loadingQuote;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onManageCollections;
  final VoidCallback? onRemoveFromCollection;
  final VoidCallback onRemove;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quote = snapshot?.quote;
    final name = item.localizedName(
      Localizations.localeOf(context).languageCode,
    );
    final stale = watchlistStaleFreshnessLabel(
      l10n,
      snapshot?.response?.freshness,
    );
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final price = quote != null
        ? MoneyText(
            amount: quote.price.toDouble(),
            currencyCode: quote.currency,
            style: TypographyTokens.numericBodyStrong,
          )
        : Text(loadingQuote ? '…' : '—', style: context.labelStyle);
    final change = quote?.changePercent;
    final nameLabel = Text(
      name ?? watchlistMarketLabel(l10n, item.market),
      style: context.captionStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final changeLabel = change == null
        ? const Text('—')
        : DeltaText.percentFromRatio(
            key: ValueKey('watchlist-row-change-${item.id}'),
            ratio: change.toDouble(),
            style: TypographyTokens.numericCaptionStrong,
          );
    return Semantics(
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? context.theme.colors.secondary
              : context.theme.colors.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: AppTappable(
          selected: selected,
          onPress: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s12,
              AppSpacing.s12,
              0,
              AppSpacing.s12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    item.displaySymbol,
                                    key: ValueKey(
                                      'watchlist-symbol-${item.id}',
                                    ),
                                    style: context.labelStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (item.alertRules.enabled &&
                                    item.alertRules.hasRule) ...[
                                  const SizedBox(width: AppSpacing.s6),
                                  Tooltip(
                                    message: l10n.watchlistAlertSetBadge,
                                    child: Icon(
                                      FLucideIcons.bellRing,
                                      size: AppIconSizes.sm,
                                      color:
                                          context.theme.colors.mutedForeground,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s8),
                          if (!largeText) price,
                        ],
                      ),
                      if (largeText) ...[
                        const SizedBox(height: AppSpacing.s4),
                        nameLabel,
                        price,
                        Wrap(
                          spacing: AppSpacing.s12,
                          runSpacing: AppSpacing.s4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            WatchlistTrend(item: item),
                            changeLabel,
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: AppSpacing.s4),
                        Row(
                          children: [
                            Expanded(child: nameLabel),
                            const SizedBox(width: AppSpacing.s8),
                            WatchlistTrend(item: item),
                            const SizedBox(width: AppSpacing.s8),
                            SizedBox(
                              width: MediaQuery.textScalerOf(context).scale(96),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: changeLabel,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (stale != null)
                        AppBadge(
                          key: ValueKey('watchlist-row-stale-${item.id}'),
                          label: stale,
                          tone: AppBadgeTone.warning,
                          size: AppBadgeSize.compact,
                        ),
                    ],
                  ),
                ),
                WatchlistRowActions(
                  item: item,
                  onEdit: onEdit,
                  onManageCollections: onManageCollections,
                  onRemoveFromCollection: onRemoveFromCollection,
                  onRemove: onRemove,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WatchlistRowActions extends StatelessWidget {
  const WatchlistRowActions({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onManageCollections,
    required this.onRemoveFromCollection,
    required this.onRemove,
  });
  final WatchlistItem item;
  final VoidCallback onEdit;
  final VoidCallback onManageCollections;
  final VoidCallback? onRemoveFromCollection;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = l10n.watchlistRowActionsTitle(item.displaySymbol);
    return AppAdaptiveActionMenu(
      title: title,
      actions: [
        AppAdaptiveAction(
          icon: FLucideIcons.bell,
          title: l10n.watchlistEditAlertsAction,
          subtitle: l10n.watchlistReminderForeground,
          onPress: onEdit,
        ),
        AppAdaptiveAction(
          icon: FLucideIcons.layers,
          title: l10n.watchlistManageCollectionsAction,
          onPress: onManageCollections,
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
          tooltip: title,
          onPress: openMenu,
          size: appActionTargetSize(context),
          iconSize: AppIconSizes.sm,
        ),
      ),
    );
  }
}

/// Reserved even without history, so asynchronous data never shifts columns.
class WatchlistTrend extends ConsumerWidget {
  const WatchlistTrend({super.key, required this.item});
  final WatchlistItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values =
        ref.watch(watchlistSparklineProvider(watchlistSymbolKey(item))).value ??
        const <double>[];
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: values.length < 2
          ? l10n.watchlistHistoryUnavailable
          : l10n.watchlistDetailTrendTitle,
      child: SizedBox(
        key: ValueKey('watchlist-trend-${item.id}'),
        width: 52,
        height: 26,
        child: values.length < 2 ? null : NwSparkline(values: values),
      ),
    );
  }
}

class WatchlistSymbolView extends StatelessWidget {
  const WatchlistSymbolView({
    super.key,
    required this.item,
    required this.snapshot,
    required this.loadingQuote,
    required this.onEdit,
    required this.onManageCollections,
    required this.onRemoveFromCollection,
    required this.onRemove,
    this.showActions = true,
  });
  final WatchlistItem item;
  final WatchlistQuoteSnapshot? snapshot;
  final bool loadingQuote;
  final VoidCallback onEdit;
  final VoidCallback onManageCollections;
  final VoidCallback? onRemoveFromCollection;
  final VoidCallback onRemove;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    final quote = snapshot?.quote;
    final name = item.localizedName(
      Localizations.localeOf(context).languageCode,
    );
    final metrics = <AppMetricItem>[
      if (quote?.open case final open?)
        AppMetricItem(
          label: l10n.watchlistDetailOpen,
          value: formatters.currency(open, code: quote!.currency),
        ),
      if (quote?.dayHigh case final high?)
        AppMetricItem(
          label: l10n.watchlistDetailHigh,
          value: formatters.currency(high, code: quote!.currency),
        ),
      if (quote?.dayLow case final low?)
        AppMetricItem(
          label: l10n.watchlistDetailLow,
          value: formatters.currency(low, code: quote!.currency),
        ),
      if (quote?.previousClose case final close?)
        AppMetricItem(
          label: l10n.watchlistDetailPreviousClose,
          value: formatters.currency(close, code: quote!.currency),
        ),
      if (quote?.volume case final volume?)
        AppMetricItem(
          label: l10n.watchlistDetailVolume,
          value: formatters.compact(volume),
        ),
      if (quote?.exchange case final exchange?)
        AppMetricItem(label: l10n.watchlistDetailExchange, value: exchange),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name ?? item.displaySymbol,
                    style: context.titleLabelStyle,
                  ),
                  Text(
                    '${item.displaySymbol} · ${watchlistMarketLabel(l10n, item.market)}',
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
            if (showActions)
              WatchlistRowActions(
                item: item,
                onEdit: onEdit,
                onManageCollections: onManageCollections,
                onRemoveFromCollection: onRemoveFromCollection,
                onRemove: onRemove,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s20),
        if (quote != null) ...[
          Wrap(
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MoneyText(
                amount: quote.price.toDouble(),
                currencyCode: quote.currency,
                style: context.theme.typography.body.xl,
              ),
              if (quote.changePercent case final change?)
                DeltaChip(
                  key: ValueKey('watchlist-detail-change-${item.id}'),
                  value: change.toDouble() * 100,
                  fractionDigits: 2,
                ),
            ],
          ),
          Text(
            '${l10n.watchlistDetailUpdatedAt} · ${formatters.dateTime(quote.asOf.toLocal())}',
            style: context.captionStyle,
          ),
          if (watchlistStaleFreshnessLabel(l10n, snapshot?.response?.freshness)
              case final stale?)
            Text(stale, style: context.captionStyle),
        ] else
          Text(
            loadingQuote
                ? l10n.watchlistOverviewFreshnessNone
                : l10n.watchlistPriceUnavailable,
            style: context.captionStyle,
          ),
        const SizedBox(height: AppSpacing.s20),
        _WatchlistPriceChart(item: item),
        const SizedBox(height: AppSpacing.s20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >= 420 &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.3
                ? 3
                : 2;
            return Column(
              children: [
                for (var i = 0; i < metrics.length; i += columns)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s16),
                    child: AppMetricCluster(
                      dense: true,
                      items: metrics.skip(i).take(columns).toList(),
                    ),
                  ),
              ],
            );
          },
        ),
        if (showActions) ...[
          const AppDivider(horizontalPadding: 0),
          const SizedBox(height: AppSpacing.s12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_alertSummary(l10n), style: context.captionLabelStyle),
                    Text(
                      l10n.watchlistReminderForeground,
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              FButton(
                variant: FButtonVariant.outline,
                onPress: onEdit,
                child: Text(l10n.watchlistEditAlertsAction),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _alertSummary(AppLocalizations l10n) {
    final rules = item.alertRules;
    if (!rules.enabled || !rules.hasRule) return l10n.watchlistAlertNotSet;
    return [
      if (rules.above case final above?) l10n.watchlistAlertAboveChip('$above'),
      if (rules.below case final below?) l10n.watchlistAlertBelowChip('$below'),
    ].join(' · ');
  }
}

class _WatchlistPriceChart extends ConsumerWidget {
  const _WatchlistPriceChart({required this.item});
  final WatchlistItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(
      watchlistHistoryProvider(watchlistSymbolKey(item)),
    );
    final bars = history.value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.watchlistDetailTrendTitle, style: context.captionLabelStyle),
        const SizedBox(height: AppSpacing.s12),
        SizedBox(
          height: 180,
          child: history.isLoading && bars.isEmpty
              ? const Center(child: FCircularProgress())
              : bars.length < 2
              ? Center(
                  child: Text(
                    l10n.watchlistHistoryUnavailable,
                    style: context.captionStyle,
                  ),
                )
              : NwLineChart(
                  key: const ValueKey('watchlist-detail-chart'),
                  semanticLabel: l10n.watchlistDetailTrendTitle,
                  interpolation: ChartInterpolation.linear,
                  showDots: false,
                  showXAxis: false,
                  showYAxis: false,
                  showTouchXAxisLabel: true,
                  xAxis: TimeAxis(
                    format: AxisDateFormat.dayMonth,
                    locale: Localizations.localeOf(context).toLanguageTag(),
                    maxLabels: 3,
                  ),
                  series: [
                    ChartSeries(
                      name: item.displaySymbol,
                      points: [
                        for (final bar in bars)
                          ChartPoint(
                            x: bar.asOf.millisecondsSinceEpoch.toDouble(),
                            y: bar.close.toDouble(),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
        if (bars.length >= 2) ...[
          const SizedBox(height: AppSpacing.s8),
          Row(
            children: [
              Expanded(
                child: Text(
                  AppFormatters(locale: Localizations.localeOf(context))
                      .date(bars.first.asOf.toLocal()),
                  style: context.captionStyle,
                ),
              ),
              Expanded(
                child: Text(
                  AppFormatters(locale: Localizations.localeOf(context))
                      .date(bars.last.asOf.toLocal()),
                  style: context.captionStyle,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
