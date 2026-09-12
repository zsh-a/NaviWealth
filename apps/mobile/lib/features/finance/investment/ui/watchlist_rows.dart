import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../data/watchlist_providers.dart';
import '../data/watchlist_repository.dart';
import 'watchlist_labels.dart';

/// One symbol in the list.
///
/// Two rows of chrome became none: the 40dp leading tile was the *same*
/// line-chart glyph on every market, and the trailing freshness chip published
/// the quote pipeline's state to the user, redundantly with the overview card.
/// The freed width went to a trend line, which is the thing a watchlist is
/// actually for, and the whole row is now a single tap target instead of only
/// the symbol text.
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
  });

  final WatchlistItem item;
  final WatchlistQuoteSnapshot? snapshot;
  final bool loadingQuote;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onManageCollections;
  final VoidCallback? onRemoveFromCollection;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quote = snapshot?.quote;
    final itemName = item.localizedName(
      Localizations.localeOf(context).languageCode,
    );
    final hasAlert = item.alertRules.enabled && item.alertRules.hasRule;
    final actionsTitle = l10n.watchlistRowActionsTitle(item.displaySymbol);
    return AppTappable(
      onPress: onOpen,
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          itemName ?? item.displaySymbol,
                          style: context.labelStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasAlert)
                        Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.s6),
                          child: Semantics(
                            label: l10n.watchlistAlertSetBadge,
                            child: Icon(
                              FLucideIcons.bellRing,
                              size: AppIconSizes.sm,
                              color: context.theme.colors.mutedForeground,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    itemName == null
                        ? watchlistMarketLabel(l10n, item.market)
                        : '${item.displaySymbol} · '
                              '${watchlistMarketLabel(l10n, item.market)}',
                    style: context.captionStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (watchlistStaleFreshnessLabel(
                        l10n,
                        snapshot?.response?.freshness,
                      )
                      case final stale?)
                    AppBadge(
                      key: ValueKey<String>('watchlist-row-stale-${item.id}'),
                      label: stale,
                      tone: AppBadgeTone.warning,
                      size: AppBadgeSize.compact,
                    ),
                ],
              ),
            ),
            WatchlistTrend(item: item, snapshot: snapshot),
            const SizedBox(width: AppSpacing.s12),
            if (loadingQuote)
              const SizedBox(
                width: AppIconSizes.h18,
                height: AppIconSizes.h18,
                child: FCircularProgress(),
              )
            else if (quote == null)
              Text(
                l10n.watchlistPriceUnavailable,
                style: context.theme.typography.body.sm,
              )
            else
              _PriceCell(item: item, quote: quote),
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
      ),
    );
  }
}

class WatchlistTrend extends ConsumerWidget {
  const WatchlistTrend({super.key, required this.item, required this.snapshot});

  final WatchlistItem item;
  final WatchlistQuoteSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final values = snapshot?.hasSparkline == true
        ? snapshot!.sparkline
        : ref
                  .watch(
                    watchlistSparklineProvider((
                      market: item.market,
                      symbol: item.symbol,
                    )),
                  )
                  .value ??
              const <double>[];
    if (values.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.s8),
      child: NwSparkline(values: values),
    );
  }
}

class _PriceCell extends StatelessWidget {
  const _PriceCell({required this.item, required this.quote});

  final WatchlistItem item;
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final changePercent = quote.changePercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        MoneyText(
          amount: quote.price.toDouble(),
          currencyCode: quote.currency,
          style: context.theme.typography.body.md,
        ),
        if (changePercent != null) ...[
          const SizedBox(height: AppSpacing.s2),
          DeltaText.percentFromRatio(
            key: ValueKey<String>('watchlist-row-change-${item.id}'),
            ratio: changePercent.toDouble(),
            style: TypographyTokens.numericCaptionStrong,
          ),
        ],
      ],
    );
  }
}

/// Everything known about one watched symbol.
///
/// Shared by the mobile sheet and the desktop detail pane so the two can never
/// disagree, and so the phone finally has somewhere to go: tapping a row used
/// to be a dead end below the master/detail breakpoint.
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
    final itemName = item.localizedName(
      Localizations.localeOf(context).languageCode,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          itemName ?? item.displaySymbol,
          style: context.theme.typography.body.xl,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          itemName == null
              ? watchlistMarketLabel(l10n, item.market)
              : '${item.displaySymbol} · '
                    '${watchlistMarketLabel(l10n, item.market)}',
          style: context.captionStyle,
        ),
        const SizedBox(height: AppSpacing.s16),
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
        else ...[
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
          const SizedBox(height: AppSpacing.s12),
          Align(
            alignment: Alignment.centerLeft,
            child: WatchlistTrend(item: item, snapshot: snapshot),
          ),
          Text(l10n.watchlistDetailTrendTitle, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s16),
          AppMetricCluster(
            axis: Axis.vertical,
            dense: true,
            items: [
              if (quote.open case final open?)
                AppMetricItem(
                  label: l10n.watchlistDetailOpen,
                  value: formatters.currency(open, code: quote.currency),
                ),
              if (quote.dayHigh case final high?)
                AppMetricItem(
                  label: l10n.watchlistDetailHigh,
                  value: formatters.currency(high, code: quote.currency),
                ),
              if (quote.dayLow case final low?)
                AppMetricItem(
                  label: l10n.watchlistDetailLow,
                  value: formatters.currency(low, code: quote.currency),
                ),
              if (quote.previousClose case final previousClose?)
                AppMetricItem(
                  label: l10n.watchlistDetailPreviousClose,
                  value: formatters.currency(
                    previousClose,
                    code: quote.currency,
                  ),
                ),
              if (quote.volume case final volume?)
                AppMetricItem(
                  label: l10n.watchlistDetailVolume,
                  value: formatters.compact(volume),
                ),
              if (quote.exchange case final exchange?)
                AppMetricItem(
                  label: l10n.watchlistDetailExchange,
                  value: exchange,
                ),
              AppMetricItem(
                label: l10n.watchlistDetailUpdatedAt,
                value: formatters.time(quote.asOf.toLocal()),
              ),
            ],
          ),
          if (watchlistStaleFreshnessLabel(l10n, snapshot?.response?.freshness)
              case final freshness?) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(freshness, style: context.captionStyle),
          ],
        ],
        const SizedBox(height: AppSpacing.s16),
        Text(_alertSummary(l10n), style: context.captionStyle),
        if (showActions) ...[
          const SizedBox(height: AppSpacing.s16),
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
            child: Flexible(
              child: Text(
                l10n.watchlistEditAlertsAction,
                textAlign: TextAlign.center,
              ),
            ),
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
      ],
    );
  }

  String _alertSummary(AppLocalizations l10n) {
    final rules = item.alertRules;
    if (!rules.enabled || !rules.hasRule) return l10n.watchlistAlertNotSet;
    final parts = <String>[
      if (rules.above case final above?) l10n.watchlistAlertAboveChip('$above'),
      if (rules.below case final below?) l10n.watchlistAlertBelowChip('$below'),
    ];
    return parts.join(' · ');
  }
}
