import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
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
        onSubmit: () async {
          Navigator.of(sheetCtx).pop();
          await showTradeJournalSheet(context, prefilled: opportunity);
        },
      ),
      child: _DetailBody(opportunity: opportunity),
    ),
  );
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.opportunity});

  final OptionsOpportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final exp = opportunity.explanation;
    final metrics = opportunity.metrics;
    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            title: l10n.incomePlannerDetailWorstCase,
            color: colors.destructive,
            child: Text(
              exp.worstCase,
              style: context.theme.typography.sm.copyWith(height: 1.4),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          _StatsGrid(
            entries: <(String, Widget)>[
              (
                l10n.incomePlannerMetricStrike,
                MoneyText(
                  amount: opportunity.contract.strike.amount.toDouble(),
                  currencyCode: opportunity.contract.strike.currency,
                  symbolStyle: MoneySymbolStyle.isoCode,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              (
                l10n.incomePlannerMetricBreakeven,
                MoneyText(
                  amount: metrics.breakeven.amount.toDouble(),
                  currencyCode: metrics.breakeven.currency,
                  symbolStyle: MoneySymbolStyle.isoCode,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              (
                l10n.incomePlannerMetricCash,
                MoneyText(
                  amount: metrics.cashRequired.amount.toDouble(),
                  currencyCode: metrics.cashRequired.currency,
                  symbolStyle: MoneySymbolStyle.isoCode,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              (
                l10n.incomePlannerMetricAnnualized,
                Text(
                  _pct(metrics.annualizedYield),
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              (
                l10n.incomePlannerMetricMargin,
                Text(
                  _pct(metrics.marginOfSafety),
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              (
                l10n.incomePlannerMetricDte,
                Text(
                  '${opportunity.contract.dte}',
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
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
          const SizedBox(height: AppSpacing.s4),
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
        Text(
          title,
          style: context.theme.typography.xs.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
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
            width: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.$1,
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
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
            child: Text(
              '• $line',
              style: context.theme.typography.sm.copyWith(height: 1.45),
            ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label：',
          style: context.theme.typography.xs.copyWith(
            color: context.theme.colors.mutedForeground,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: context.theme.typography.sm.copyWith(height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _ScoreBreakdown extends StatelessWidget {
  const _ScoreBreakdown({required this.breakdown});

  final Map<String, Decimal> breakdown;

  @override
  Widget build(BuildContext context) {
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
                  width: 96,
                  child: Text(
                    entry.key,
                    style: context.theme.typography.xs.copyWith(
                      color: context.theme.colors.mutedForeground,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: LinearProgressIndicator(
                      value: entry.value.toDouble().clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: context.theme.colors.muted,
                      color: context.theme.colors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  _pct(entry.value),
                  style: context.theme.typography.xs.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _pct(Decimal value) {
  final pct = (value * Decimal.fromInt(100)).toStringAsFixed(1);
  return '$pct%';
}
