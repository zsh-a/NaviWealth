import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/options_strategy_profile.dart';
import '../domain/options_trade_stats.dart';
import 'income_planner_labels.dart';

class OptionsTradeStatsPage extends ConsumerWidget {
  const OptionsTradeStatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (kIsWeb) {
      return AppPageScaffold(
        title: l10n.incomePlannerStatsTitle,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s24),
          child: Text(l10n.incomePlannerUnsupportedOnWeb),
        ),
      );
    }
    final statsAsync = ref.watch(optionsTradeStatsProvider);
    return AppPageScaffold(
      title: l10n.incomePlannerStatsTitle,
      childPad: false,
      child: statsAsync.whenOrLoading(
        error: (error, _) => Center(
          child: AppEmptyState.error(
            title: l10n.commonLoadFailed,
            message: '$error',
          ),
        ),
        data: (stats) {
          if (stats.isEmpty) {
            return Center(
              child: AppEmptyState(
                icon: FLucideIcons.chartNoAxesColumnIncreasing,
                title: l10n.incomePlannerStatsEmptyTitle,
                message: l10n.incomePlannerStatsEmptyBody,
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              AppSpacing.s12,
              AppSpacing.s16,
              AppSpacing.s24,
            ),
            children: [
              _OverviewCard(stats: stats),
              const SizedBox(height: AppSpacing.s16),
              SectionHeader(title: l10n.incomePlannerStatsStrategySectionTitle),
              const SizedBox(height: AppSpacing.s4),
              for (final item in stats.byStrategy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                  child: _StrategyTile(item: item),
                ),
              const SizedBox(height: AppSpacing.s16),
              SectionHeader(title: l10n.incomePlannerStatsSymbolSectionTitle),
              const SizedBox(height: AppSpacing.s4),
              for (final item in stats.bySymbol.take(12))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                  child: _SymbolTile(item: item),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.stats});

  final OptionsTradeStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = stats.primaryCurrency;
    final formatters = AppFormatters(
      locale: Localizations.localeOf(context),
      baseCurrency: primary?.currency ?? 'CNY',
    );
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.incomePlannerStatsOverviewTitle, style: context.labelStyle),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s12,
            runSpacing: AppSpacing.s12,
            children: [
              _Metric(
                label: l10n.incomePlannerStatsTotalTrades,
                value: '${stats.totalEntries}',
              ),
              _Metric(
                label: l10n.incomePlannerStatsOpenTrades,
                value: '${stats.openEntries}',
              ),
              _Metric(
                label: l10n.incomePlannerStatsAssignedTrades,
                value: '${stats.assignedEntries}',
              ),
              _Metric(
                label: l10n.incomePlannerStatsExpiredTrades,
                value: '${stats.expiredEntries}',
              ),
              if (primary != null) ...[
                _Metric(
                  label: l10n.incomePlannerStatsPremium,
                  value: _money(
                    primary.totalPremium,
                    primary.currency,
                    formatters,
                  ),
                ),
                _Metric(
                  label: l10n.incomePlannerStatsRealizedPnl,
                  value: _signedMoney(
                    primary.trackedRealizedPnl,
                    primary.currency,
                    formatters,
                  ),
                ),
                _Metric(
                  label: l10n.incomePlannerStatsWinRate,
                  value: _pct(primary.winRate, formatters),
                ),
                _Metric(
                  label: l10n.incomePlannerStatsAvgHoldingDays,
                  value: primary.averageHoldingDays == null
                      ? '—'
                      : formatters.number(
                          primary.averageHoldingDays!,
                          decimalDigits: 1,
                        ),
                ),
              ],
            ],
          ),
          if (stats.byCurrency.length > 1) ...[
            const SizedBox(height: AppSpacing.s12),
            Text(
              l10n.incomePlannerStatsMultiCurrencyNote(
                stats.byCurrency.map((s) => s.currency).join(', '),
              ),
              style: context.captionStyle.copyWith(height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _StrategyTile extends StatelessWidget {
  const _StrategyTile({required this.item});

  final OptionsStrategyStats item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      borderRadius: AppRadius.md,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _strategyLabel(l10n, item.strategy),
                  style: context.labelStyle,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  l10n.incomePlannerStatsTradeCount(
                    item.entryCount,
                    item.openCount,
                  ),
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          _MoneyColumn(
            label: l10n.incomePlannerStatsRealizedPnl,
            values: item.trackedRealizedPnlByCurrency,
            signed: true,
          ),
        ],
      ),
    );
  }
}

class _SymbolTile extends StatelessWidget {
  const _SymbolTile({required this.item});

  final OptionsSymbolStats item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      borderRadius: AppRadius.md,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.symbol, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  l10n.incomePlannerStatsSymbolDetail(
                    item.entryCount,
                    item.openCount,
                    item.assignedCount,
                    item.expiredCount,
                  ),
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          _MoneyColumn(
            label: l10n.incomePlannerStatsPremium,
            values: item.totalPremiumByCurrency,
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppControlWidths.statsTile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.captionStyle),
          const SizedBox(height: AppSpacing.s2),
          Text(value, style: context.labelStyle, maxLines: 1),
        ],
      ),
    );
  }
}

class _MoneyColumn extends StatelessWidget {
  const _MoneyColumn({
    required this.label,
    required this.values,
    this.signed = false,
  });

  final String label;
  final Map<String, Decimal> values;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final formatters = AppFormatters(locale: Localizations.localeOf(context));
    return SizedBox(
      width: AppControlWidths.scenarioSuffix,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: context.captionStyle, textAlign: TextAlign.end),
          const SizedBox(height: AppSpacing.s2),
          Text(
            values.isEmpty
                ? '—'
                : _moneyMap(values, formatters, signed: signed),
            style: context.labelStyle,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

String _strategyLabel(AppLocalizations l10n, OptionsStrategyKind strategy) {
  return optionsStrategyKindShortLabel(l10n, strategy);
}

String _moneyMap(
  Map<String, Decimal> values,
  AppFormatters formatters, {
  bool signed = false,
}) {
  final entries = values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries
      .map(
        (entry) => signed
            ? _signedMoney(entry.value, entry.key, formatters)
            : _money(entry.value, entry.key, formatters),
      )
      .join(' · ');
}

String _money(Decimal amount, String currency, AppFormatters formatters) {
  return formatters.currency(amount, code: currency);
}

String _signedMoney(Decimal amount, String currency, AppFormatters formatters) {
  return formatters.signedMoney(amount, unit: currency);
}

String _pct(double? value, AppFormatters formatters) {
  if (value == null) return '—';
  return formatters.percent(value, decimalDigits: 1);
}
