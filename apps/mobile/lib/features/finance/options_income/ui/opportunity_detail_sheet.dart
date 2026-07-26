import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/core/format/providers.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import '../domain/options_opportunity.dart';
import 'trade_journal_sheet.dart';

/// Detail sheet for a single [OptionsOpportunity]. Surfaced from the
/// opportunity card; the body is read-only so it doesn't need a
/// FormDirtyController.
Future<void> showOpportunityDetailSheet(
  BuildContext context,
  OptionsOpportunity opportunity,
) {
  final l10n = AppLocalizations.of(context);
  return showAppFormSheet(
    context: context,
    builder: (sheetCtx) => AppSheet(
      title: opportunity.explanation.summary,
      footer: AppSheetFooter(
        submitLabel: l10n.incomePlannerDetailLogTrade,
        cancelLabel: l10n.commonCancel,
        onSubmit: () => closeSheetThen(sheetCtx, () async {
          if (!context.mounted) return;
          await showTradeJournalSheet(context, prefilled: opportunity);
        }),
      ),
      child: _DetailBody(opportunity: opportunity),
    ),
  );
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.opportunity});

  final OptionsOpportunity opportunity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final exp = opportunity.explanation;
    final metrics = opportunity.metrics;
    final colors = context.theme.colors;
    final contract = opportunity.contract;
    final expiry = MaterialLocalizations.of(
      context,
    ).formatShortDate(contract.expiration.toLocal());
    String pct(Decimal value) =>
        formatters.percent(value.toDouble(), decimalDigits: 1);
    String money(Money value) =>
        formatters.currency(value.amount, code: value.currency);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            title: l10n.incomePlannerDetailWorstCase,
            color: colors.destructive,
            child: Text(exp.worstCase, style: context.bodyCaptionStyle),
          ),
          const SizedBox(height: AppSpacing.s16),
          _StatsGrid(
            entries: <(String, Widget)>[
              (
                l10n.incomePlannerMetricPremiumTotal,
                MoneyText(
                  amount: metrics.premium.amount.toDouble(),
                  currencyCode: metrics.premium.currency,
                  symbolStyle: MoneySymbolStyle.isoCode,
                  style: context.labelStyle,
                ),
              ),
              (
                l10n.incomePlannerMetricAnnualized,
                Text(pct(metrics.annualizedYield), style: context.labelStyle),
              ),
              (
                l10n.incomePlannerMetricBreakeven,
                MoneyText(
                  amount: metrics.breakeven.amount.toDouble(),
                  currencyCode: metrics.breakeven.currency,
                  symbolStyle: MoneySymbolStyle.isoCode,
                  style: context.labelStyle,
                ),
              ),
              (
                l10n.incomePlannerMetricCash,
                MoneyText(
                  amount: metrics.cashRequired.amount.toDouble(),
                  currencyCode: metrics.cashRequired.currency,
                  symbolStyle: MoneySymbolStyle.isoCode,
                  style: context.labelStyle,
                ),
              ),
              (
                l10n.incomePlannerMetricMargin,
                Text(pct(metrics.marginOfSafety), style: context.labelStyle),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s16),
          _Section(
            title: l10n.incomePlannerDetailContractSection,
            color: colors.mutedForeground,
            child: _StatsGrid(
              entries: <(String, Widget)>[
                (
                  l10n.incomePlannerMetricUnderlyingPrice,
                  MoneyText(
                    amount: contract.underlyingPrice.amount.toDouble(),
                    currencyCode: contract.underlyingPrice.currency,
                    symbolStyle: MoneySymbolStyle.isoCode,
                    style: context.labelStyle,
                  ),
                ),
                (
                  l10n.incomePlannerMetricStrike,
                  MoneyText(
                    amount: contract.strike.amount.toDouble(),
                    currencyCode: contract.strike.currency,
                    symbolStyle: MoneySymbolStyle.isoCode,
                    style: context.labelStyle,
                  ),
                ),
                (
                  l10n.incomePlannerMetricOptionPrice,
                  MoneyText(
                    amount: contract.mid.amount.toDouble(),
                    currencyCode: contract.mid.currency,
                    symbolStyle: MoneySymbolStyle.isoCode,
                    style: context.labelStyle,
                  ),
                ),
                (
                  l10n.incomePlannerMetricDte,
                  Text('${contract.dte}', style: context.labelStyle),
                ),
                (
                  l10n.incomePlannerMetricExpiration,
                  Text(expiry, style: context.labelStyle),
                ),
                (
                  l10n.incomePlannerMetricDelta,
                  Text(
                    contract.delta?.toStringAsFixed(2) ?? '—',
                    style: context.labelStyle,
                  ),
                ),
                (
                  l10n.incomePlannerMetricIv,
                  Text(
                    contract.impliedVolatility == null
                        ? '—'
                        : pct(contract.impliedVolatility!),
                    style: context.labelStyle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          _Section(
            title: l10n.incomePlannerDetailLiquiditySection,
            color: colors.mutedForeground,
            child: _StatsGrid(
              entries: <(String, Widget)>[
                (
                  l10n.incomePlannerMetricBidAsk,
                  Text(
                    '${money(contract.bid)} / ${money(contract.ask)}',
                    style: context.labelStyle,
                  ),
                ),
                (
                  l10n.incomePlannerMetricSpread,
                  Text(
                    pct(contract.bidAskSpreadPct),
                    style: context.labelStyle,
                  ),
                ),
                (
                  l10n.incomePlannerMetricOpenInterest,
                  Text('${contract.openInterest}', style: context.labelStyle),
                ),
                (
                  l10n.incomePlannerMetricVolume,
                  Text('${contract.volume}', style: context.labelStyle),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          _Section(
            title: l10n.incomePlannerDetailWhyGood,
            color: colors.primary,
            child: _Bullets(exp.whyGood),
          ),
          if (exp.whyRisky.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            _Section(
              title: l10n.incomePlannerDetailWhyRisky,
              color: colors.destructive,
              child: _Bullets(exp.whyRisky),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          _LabeledLine(
            label: l10n.incomePlannerDetailBestFor,
            value: exp.bestFor,
          ),
          const SizedBox(height: AppSpacing.s8),
          _LabeledLine(
            label: l10n.incomePlannerDetailAvoidIf,
            value: exp.avoidIf,
          ),
          const SizedBox(height: AppSpacing.s16),
          _Section(
            title: l10n.incomePlannerDetailScoreBreakdown,
            color: colors.mutedForeground,
            child: _ScoreBreakdown(breakdown: exp.scoreBreakdown),
          ),
          const SizedBox(height: AppSpacing.s24),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.color,
    required this.child,
  });

  final String title;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.captionLabelStyle.copyWith(color: color)),
        const SizedBox(height: AppSpacing.s4),
        child,
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.entries});

  final List<(String, Widget)> entries;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s12,
      runSpacing: AppSpacing.s12,
      children: [
        for (final e in entries)
          SizedBox(
            width: AppControlWidths.statsTile,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.$1, style: context.captionStyle),
                const SizedBox(height: AppSpacing.s2),
                e.$2,
              ],
            ),
          ),
      ],
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.lines);

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
            child: Text('• $line', style: context.bodyCaptionStyle),
          ),
      ],
    );
  }
}

class _LabeledLine extends StatelessWidget {
  const _LabeledLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.captionLabelStyle.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(value, style: context.bodyCaptionStyle),
      ],
    );
  }
}

class _ScoreBreakdown extends ConsumerWidget {
  const _ScoreBreakdown({required this.breakdown});

  final Map<String, Decimal> breakdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formatters = context.formatters(ref);
    final sorted = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: [
        for (final entry in sorted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
            child: Row(
              children: [
                SizedBox(
                  width: AppControlWidths.detailLabel,
                  child: Text(
                    _scoreLabel(context, entry.key),
                    style: context.captionStyle,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: FDeterminateProgress(
                      value: entry.value.toDouble().clamp(0.0, 1.0),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  formatters.percent(entry.value.toDouble(), decimalDigits: 1),
                  style: context.captionLabelStyle,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _scoreLabel(BuildContext context, String key) {
  final l10n = AppLocalizations.of(context);
  return switch (key) {
    'yield' => l10n.incomePlannerScoreYield,
    'liquidity' => l10n.incomePlannerScoreLiquidity,
    'safety_margin' || 'safetyMargin' => l10n.incomePlannerScoreSafetyMargin,
    'iv' => l10n.incomePlannerScoreIv,
    'portfolio_fit' || 'portfolioFit' => l10n.incomePlannerScorePortfolioFit,
    'event_safety' || 'eventSafety' => l10n.incomePlannerScoreEventSafety,
    _ => key,
  };
}
