import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_coordinator.dart';
import 'package:naviwealth/features/finance/data/market/sync/price_sync_providers.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart' as dom;

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Historical FX-rate surface.
///
/// Rates are grouped by currency pair rather than rendered as one long
/// undifferentiated table. The chart answers "what changed?" at a glance;
/// the flat history rows below it keep every stored observation auditable and
/// swipe-deletable.
class FxRatesPage extends ConsumerStatefulWidget {
  const FxRatesPage({super.key});

  @override
  ConsumerState<FxRatesPage> createState() => _FxRatesPageState();
}

class _FxRatesPageState extends ConsumerState<FxRatesPage> {
  _FxRange _range = _FxRange.thirtyDays;
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ratesAsync = ref.watch(fxRatesStreamProvider);
    final syncAsync = ref.watch(priceSyncStatusEventStreamProvider);
    final formatters = context.formatters(ref);

    return AppPageScaffold(
      title: l10n.fxRatesAppBarTitle,
      actions: [
        AppHeaderAction(
          semanticsLabel: l10n.commonRefresh,
          icon: Icon(
            _refreshing ? FLucideIcons.loaderCircle : FLucideIcons.refreshCw,
          ),
          onPress: _refreshing ? null : _refresh,
        ),
      ],
      childPad: false,
      child: ratesAsync.whenOrError(
        context: context,
        data: (rates) => _RatesContent(
          rates: rates,
          range: _range,
          baseCurrency: ref.watch(baseCurrencyProvider),
          formatters: formatters,
          syncStatus: syncAsync.value?.status,
          lastSyncAt: syncAsync.value?.lastSuccessAt,
          onRangeChanged: (range) => setState(() => _range = range),
          onDelete: _deleteRate,
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _refreshing = true);
    AppMessenger.show(context, ToastKind.info, l10n.fxRatesRefreshing);
    try {
      final coordinator = await ref.read(priceSyncCoordinatorProvider.future);
      if (!mounted) return;
      await coordinator.triggerNow(reason: PriceSyncReason.manual);
      if (!mounted) return;
      final status = ref.read(priceSyncStatusBusProvider).current;
      if (status.status == PriceSyncStatus.failed) {
        final result = coordinator.lastFxResult;
        final message =
            result != null && result.hasFailures && result.syncedCount > 0
            ? l10n.fxRatesSyncPartial(
                result.syncedCount,
                result.requestedPairs.length,
                result.failureSummary ?? l10n.commonSafeErrorMessage,
              )
            : l10n.fxRatesSyncFailed(
                status.lastError ?? l10n.commonSafeErrorMessage,
              );
        AppMessenger.show(context, ToastKind.error, message);
      } else if (status.status == PriceSyncStatus.fresh) {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.fxRatesSyncCompleted,
        );
      }
    } catch (e) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.fxRatesSyncFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<bool> _deleteRate(dom.FxRate rate) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.fxRatesDeleteConfirmTitle),
      body: Text(l10n.fxRatesDeleteConfirmBody),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: FLucideIcons.trash2,
    );
    if (confirmed != true || !mounted) return false;
    final repo = await ref.read(fxRateRepositoryProvider.future);
    await repo.deleteByNaturalKey(
      base: rate.base,
      quote: rate.quote,
      date: rate.date,
    );
    return true;
  }
}

enum _FxRange { sevenDays, thirtyDays, ninetyDays, all }

class _RatesContent extends StatelessWidget {
  const _RatesContent({
    required this.rates,
    required this.range,
    required this.baseCurrency,
    required this.formatters,
    required this.syncStatus,
    required this.lastSyncAt,
    required this.onRangeChanged,
    required this.onDelete,
  });

  final List<dom.FxRate> rates;
  final _FxRange range;
  final String baseCurrency;
  final AppFormatters formatters;
  final PriceSyncStatus? syncStatus;
  final DateTime? lastSyncAt;
  final ValueChanged<_FxRange> onRangeChanged;
  final Future<bool> Function(dom.FxRate rate) onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pairs = _groupRates(rates);
    final latest = _latestRate(rates);
    final latestFetchedAt = _latestFetchedAt(rates);

    if (pairs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: [
          _OverviewCard(
            pairCount: 0,
            baseCurrency: baseCurrency,
            latest: null,
            lastUpdated: lastSyncAt ?? latestFetchedAt,
            formatters: formatters,
            status: syncStatus,
          ),
          const SizedBox(height: AppSpacing.s12),
          const _EmptyRatesCard(),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s16,
        AppSpacing.s32,
      ),
      children: [
        _OverviewCard(
          pairCount: pairs.length,
          baseCurrency: baseCurrency,
          latest: latest,
          lastUpdated: lastSyncAt ?? latestFetchedAt,
          formatters: formatters,
          status: syncStatus,
        ),
        const SizedBox(height: AppSpacing.s16),
        AppSection.item(
          title: l10n.fxRatesHistoryTitle,
          trailing: AppBadge(
            label: l10n.fxRatesPairsTracked(pairs.length),
            tone: AppBadgeTone.accent,
            size: AppBadgeSize.compact,
          ),
          children: [
            SegmentedRow<_FxRange>(
              options: _FxRange.values,
              value: range,
              labelOf: (value) => _rangeLabel(l10n, value),
              semanticLabelOf: (value) =>
                  '${l10n.fxRatesHistoryTitle}: ${_rangeLabel(l10n, value)}',
              minSegmentWidth: AppSpacing.s56,
              onChanged: onRangeChanged,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        for (var i = 0; i < pairs.length; i++) ...[
          _FxPairCard(
            history: _filterRange(pairs[i], range),
            fullHistory: pairs[i],
            range: range,
            formatters: formatters,
            onDelete: onDelete,
          ),
          if (i != pairs.length - 1) const SizedBox(height: AppSpacing.s12),
        ],
      ],
    );
  }

  String _rangeLabel(AppLocalizations l10n, _FxRange range) => switch (range) {
    _FxRange.sevenDays => l10n.fxRatesRange7D,
    _FxRange.thirtyDays => l10n.fxRatesRange30D,
    _FxRange.ninetyDays => l10n.fxRatesRange90D,
    _FxRange.all => l10n.fxRatesRangeAll,
  };

  static List<_FxPairHistory> _groupRates(List<dom.FxRate> input) {
    final grouped = <String, List<dom.FxRate>>{};
    for (final rate in input) {
      final key = '${rate.base}|${rate.quote}';
      (grouped[key] ??= <dom.FxRate>[]).add(rate);
    }
    final histories = [
      for (final values in grouped.values)
        _FxPairHistory(
          base: values.first.base,
          quote: values.first.quote,
          rates: [...values]..sort((a, b) => a.date.compareTo(b.date)),
        ),
    ];
    histories.sort((a, b) => b.latest.date.compareTo(a.latest.date));
    return histories;
  }

  static dom.FxRate? _latestRate(List<dom.FxRate> rates) {
    if (rates.isEmpty) return null;
    return rates.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
  }

  static DateTime? _latestFetchedAt(List<dom.FxRate> rates) {
    if (rates.isEmpty) return null;
    return rates
        .map((rate) => rate.fetchedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  static _FxPairHistory _filterRange(_FxPairHistory history, _FxRange range) {
    if (range == _FxRange.all) return history;
    final days = switch (range) {
      _FxRange.sevenDays => 7,
      _FxRange.thirtyDays => 30,
      _FxRange.ninetyDays => 90,
      _FxRange.all => 0,
    };
    final cutoff = history.latest.date.subtract(Duration(days: days - 1));
    final filtered = history.rates
        .where((rate) => !rate.date.isBefore(cutoff))
        .toList(growable: false);
    return _FxPairHistory(
      base: history.base,
      quote: history.quote,
      rates: filtered.isEmpty ? [history.latest] : filtered,
    );
  }
}

class _FxPairHistory {
  const _FxPairHistory({
    required this.base,
    required this.quote,
    required this.rates,
  });

  final String base;
  final String quote;
  final List<dom.FxRate> rates;

  dom.FxRate get latest => rates.last;
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.pairCount,
    required this.baseCurrency,
    required this.latest,
    required this.lastUpdated,
    required this.formatters,
    required this.status,
  });

  final int pairCount;
  final String baseCurrency;
  final dom.FxRate? latest;
  final DateTime? lastUpdated;
  final AppFormatters formatters;
  final PriceSyncStatus? status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statusTone = switch (status) {
      PriceSyncStatus.syncing => AppBadgeTone.info,
      PriceSyncStatus.failed => AppBadgeTone.error,
      PriceSyncStatus.fresh => AppBadgeTone.success,
      _ => AppBadgeTone.neutral,
    };
    final statusLabel = switch (status) {
      PriceSyncStatus.syncing => l10n.fxRatesStatusSyncing,
      PriceSyncStatus.failed => l10n.fxRatesStatusFailed,
      PriceSyncStatus.fresh => l10n.fxRatesStatusReady,
      _ => l10n.fxRatesStatusLocal,
    };

    return SoftCard.hero(
      padding: AppPageRhythm.heroPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.theme.colors.primary.withValues(
                    alpha: AppOpacity.subtle,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.s10),
                  child: Icon(
                    FLucideIcons.arrowLeftRight,
                    size: AppIconSizes.h18,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.fxRatesOverviewTitle, style: context.labelStyle),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      l10n.fxRatesOverviewSubtitle,
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              AppBadge(
                label: statusLabel,
                tone: statusTone,
                size: AppBadgeSize.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s20),
          AppMetricCluster(
            dense: true,
            items: [
              AppMetricItem(
                label: l10n.fxRatesTrackedPairsLabel,
                value: pairCount.toString(),
              ),
              AppMetricItem(
                label: l10n.fxRatesBaseCurrencyLabel,
                value: baseCurrency.toUpperCase(),
              ),
              AppMetricItem(
                label: l10n.fxRatesLastUpdatedLabel,
                value: lastUpdated == null
                    ? '—'
                    : formatters.dateTime(lastUpdated!.toLocal()),
                maxLines: 2,
              ),
            ],
          ),
          if (latest != null) ...[
            const SizedBox(height: AppSpacing.s16),
            Text(
              '${l10n.fxRatesLatestObservation}: '
              '1 ${latest!.base} = ${latest!.rate} ${latest!.quote}',
              style: TypographyTokens.numericBodyStrong,
            ),
          ],
        ],
      ),
    );
  }
}

class _FxPairCard extends StatelessWidget {
  const _FxPairCard({
    required this.history,
    required this.fullHistory,
    required this.range,
    required this.formatters,
    required this.onDelete,
  });

  final _FxPairHistory history;
  final _FxPairHistory fullHistory;
  final _FxRange range;
  final AppFormatters formatters;
  final Future<bool> Function(dom.FxRate rate) onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final latest = history.latest;
    final baseline = history.rates.first;
    final change = baseline.rate == Decimal.zero
        ? null
        : ((latest.rate / baseline.rate).toDecimal(
                    scaleOnInfinitePrecision: 12,
                  ) -
                  Decimal.one)
              .toDouble();
    final precision = _ratePrecision(latest.rate);
    final points = [
      for (final rate in history.rates)
        ChartPoint(
          x: rate.date.millisecondsSinceEpoch.toDouble(),
          y: rate.rate.toDouble(),
          meta: rate,
        ),
    ];
    final chart = points.length < 2
        ? SizedBox(
            height: AppChartHeights.compact,
            child: EmptyChartPlaceholder(message: l10n.fxRatesNotEnoughHistory),
          )
        : SizedBox(
            height: AppChartHeights.compact,
            child: NwLineChart(
              series: [
                ChartSeries(
                  name: '${history.base}/${history.quote}',
                  points: points,
                  fillOpacity: AppOpacity.light,
                  strokeWidth: AppStroke.medium,
                ),
              ],
              xAxis: const TimeAxis(
                format: AxisDateFormat.monthYear,
                maxLabels: 4,
              ),
              yAxis: ValueAxis(
                format: ValueAxisFormat.decimal,
                fractionDigits: precision,
                maxLabels: 3,
                showGrid: true,
              ),
              filled: true,
              interpolation: ChartInterpolation.linear,
              showDots: false,
              heroDots: true,
              showYAxis: false,
              showTouchXAxisLabel: true,
              semanticLabel: '${history.base}/${history.quote}',
            ),
          );

    return SoftCard.raised(
      padding: AppPageRhythm.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${history.base} / ${history.quote}',
                      style: context.rowTitleStyle,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      l10n.fxRatesAsOfValue(formatters.date(latest.date)),
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              AppBadge(
                label: latest.source,
                tone: AppBadgeTone.neutral,
                size: AppBadgeSize.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '1 ${latest.base} = '
                  '${formatters.number(latest.rate.toDouble(), decimalDigits: precision)} '
                  '${latest.quote}',
                  style: TypographyTokens.numericTitleStrong,
                ),
              ),
              if (change != null && history.rates.length > 1)
                DeltaText.percentFromRatio(
                  ratio: change,
                  fractionDigits: 2,
                  showIcon: true,
                  style: context.captionStyle,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          chart,
          const SizedBox(height: AppSpacing.s16),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.fxRatesHistoryEntries,
                  style: context.captionStyle,
                ),
              ),
              Text(
                l10n.fxRatesEntriesCount(history.rates.length),
                style: context.microCaptionStyle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          for (var i = history.rates.length - 1; i >= 0; i--)
            _RateHistoryRow(
              rate: history.rates[i],
              precision: precision,
              formatters: formatters,
              onDelete: onDelete,
              isLast: i == 0,
            ),
          if (range != _FxRange.all &&
              history.rates.length < fullHistory.rates.length) ...[
            const SizedBox(height: AppSpacing.s6),
            Text(l10n.fxRatesRangeHint, style: context.microCaptionStyle),
          ],
        ],
      ),
    );
  }

  static int _ratePrecision(Decimal rate) {
    final raw = rate.toString();
    final dot = raw.indexOf('.');
    if (dot < 0) return 0;
    return math.min(6, raw.length - dot - 1);
  }
}

class _RateHistoryRow extends StatelessWidget {
  const _RateHistoryRow({
    required this.rate,
    required this.precision,
    required this.formatters,
    required this.onDelete,
    required this.isLast,
  });

  final dom.FxRate rate;
  final int precision;
  final AppFormatters formatters;
  final Future<bool> Function(dom.FxRate rate) onDelete;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return AppDismissible(
      itemKey: ValueKey('${rate.base}-${rate.quote}-${rate.date}'),
      borderRadius: AppRadius.sm,
      confirm: () => onDelete(rate),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(
                      color: context.theme.colors.border.withValues(
                        alpha: AppOpacity.subtle,
                      ),
                    ),
                  ),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.s8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatters.date(rate.date),
                        style: context.bodyCaptionStyle,
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        '${rate.source} · '
                        '${formatters.dateTime(rate.fetchedAt.toLocal())}',
                        style: context.microCaptionStyle,
                      ),
                    ],
                  ),
                ),
                Text(
                  rate.rate.toStringAsFixed(precision),
                  style: TypographyTokens.numericBodyStrong,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRatesCard extends StatelessWidget {
  const _EmptyRatesCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Column(
        children: [
          Icon(
            FLucideIcons.chartNoAxesCombined,
            size: AppIconSizes.xl,
            color: context.theme.colors.mutedForeground,
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.fxRatesEmpty,
            textAlign: TextAlign.center,
            style: context.bodyCaptionStyle,
          ),
        ],
      ),
    );
  }
}
