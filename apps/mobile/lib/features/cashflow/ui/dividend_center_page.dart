import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../investment/domain/dividend_forecast.dart';
import '../data/dividend_center_providers.dart';
import '../data/dividend_forecast_providers.dart';
import '../domain/dividend_center.dart';
import 'dividend_event_actions.dart';

class DividendCenterPage extends ConsumerWidget {
  const DividendCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(dividendCenterSnapshotProvider);
    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.dividendCenterTitle),
        prefixes: [backHeaderAction(context)],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.creditCard),
            onPress: () => context.push(AppRoutes.wealthCorporateAction),
          ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: PageSkeletonShell<DividendCenterSnapshot>(
          skeleton: const DividendCenterSkeleton(),
          isLoading: snapshot.isLoading,
          child: snapshot.when(
            loading: () => const DividendCenterSkeleton(),
            error: (error, _) => AppEmptyState.error(
              title: l10n.dividendCenterLoadError('$error'),
              action: FButton(
                variant: FButtonVariant.ghost,
                onPress: () => ref.invalidate(dividendCenterSnapshotProvider),
                child: Text(l10n.commonRetry),
              ),
            ),
            data: (data) => _DividendCenterBody(snapshot: data),
          ),
        ),
      ),
    );
  }
}

class _DividendCenterBody extends StatelessWidget {
  const _DividendCenterBody({required this.snapshot});

  final DividendCenterSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(AppSpacing.s16, AppSpacing.s16, AppSpacing.s16, AppSpacing.s16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: AdaptiveContentFrame(
        maxWidth: AdaptiveMaxWidth.dashboard,
        padding: EdgeInsets.zero,
        primary: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (snapshot.isEmpty)
              const _EmptyDividendState()
            else ...[
              _KpiGrid(snapshot: snapshot),
              const SizedBox(height: AppSpacing.s16),
              _RankingSection(snapshot: snapshot),
              const SizedBox(height: AppSpacing.s16),
              const _ForecastCard(),
              const SizedBox(height: AppSpacing.s16),
              _TimelineSection(snapshot: snapshot),
            ],
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends ConsumerWidget {
  const _KpiGrid({required this.snapshot});

  final DividendCenterSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final cards = <Widget>[
      _MetricCard(
        label: l10n.dividendCenterMetricYtd,
        value: formatters.currency(
          snapshot.yearToDateGross,
          code: snapshot.baseCurrency,
        ),
      ),
      _MetricCard(
        label: l10n.dividendCenterMetricTtm,
        value: formatters.currency(
          snapshot.ttmGross,
          code: snapshot.baseCurrency,
        ),
      ),
      _MetricCard(
        label: l10n.dividendCenterMetricYoy,
        value: snapshot.yearOverYearRatio == null
            ? l10n.commonNotAvailable
            : formatters.signedPercent(snapshot.yearOverYearRatio!),
      ),
      _MetricCard(
        label: l10n.dividendCenterMetricWithholding,
        value: formatters.currency(
          snapshot.ttmWithholding,
          code: snapshot.baseCurrency,
        ),
      ),
    ];
    Widget rowOf(List<Widget> children) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i != 0) const SizedBox(width: AppSpacing.s12),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
    // Intrinsic-height metric cards: never overflow a fixed aspect ratio
    // under large text-scale. Four across on wide, 2x2 below 760dp.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) return rowOf(cards);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rowOf(cards.sublist(0, 2)),
            const SizedBox(height: AppSpacing.s12),
            rowOf(cards.sublist(2, 4)),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: TypographyTokens.numericTitle),
          ),
        ],
      ),
    );
  }
}

class _RankingSection extends ConsumerWidget {
  const _RankingSection({required this.snapshot});

  final DividendCenterSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final rows = snapshot.ranking.take(8).toList();
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            title: l10n.dividendCenterHoldingRanking,
            trailing: l10n.dividendForecastStrategyTtm,
          ),
          const SizedBox(height: AppSpacing.s12),
          LayoutBuilder(
            builder: (context, constraints) {
              // Five numeric columns need room; below ~520dp fall back to
              // a two-line row instead of crushing every column.
              final compact = constraints.maxWidth < 520;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final row in rows) ...[
                    _RankRow(
                      compact: compact,
                      name: row.assetLabel,
                      amount: formatters.currency(
                        row.ttmGrossInBase,
                        code: snapshot.baseCurrency,
                      ),
                      share: formatters.percent(row.portfolioShare),
                      yieldOnCost: row.yieldOnCost == null
                          ? l10n.commonNotAvailable
                          : formatters.percent(row.yieldOnCost!),
                      withholding: formatters.currency(
                        row.withholdingInBase,
                        code: snapshot.baseCurrency,
                      ),
                    ),
                    if (row != rows.last) const SizedBox(height: AppSpacing.s16),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.compact,
    required this.name,
    required this.amount,
    required this.share,
    required this.yieldOnCost,
    required this.withholding,
  });

  final bool compact;
  final String name;
  final String amount;
  final String share;
  final String yieldOnCost;
  final String withholding;

  @override
  Widget build(BuildContext context) {
    final muted = context.theme.colors.mutedForeground;
    if (compact) {
      final detail = '$share · $yieldOnCost · $withholding';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: context.theme.typography.sm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  amount,
                  style: context.theme.typography.sm.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              detail,
              style: context.theme.typography.xs.copyWith(color: muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }
    Widget cell(String text, int flex, {Color? color}) => Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: color == null ? null : TextStyle(color: color),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              name,
              style: context.theme.typography.sm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          cell(amount, 3),
          cell(share, 2),
          cell(yieldOnCost, 2),
          cell(withholding, 3, color: muted),
        ],
      ),
    );
  }
}

class _TimelineSection extends ConsumerWidget {
  const _TimelineSection({required this.snapshot});

  final DividendCenterSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(title: l10n.dividendCenterHistoryTimeline),
          const SizedBox(height: AppSpacing.s12),
          for (final month in snapshot.months) ...[
            Text(
              formatters.monthYear(month.month),
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            for (final event in month.events)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                child: _TimelineRow(
                  date: formatters.date(event.event.date),
                  asset: event.assetLabel,
                  gross: formatters.currency(
                    event.grossInBase,
                    code: snapshot.baseCurrency,
                  ),
                  withholding: formatters.currency(
                    event.withholdingInBase,
                    code: snapshot.baseCurrency,
                  ),
                  onTap: () => showDividendEventActions(context, ref, event),
                ),
              ),
            const SizedBox(height: AppSpacing.s6),
          ],
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.date,
    required this.asset,
    required this.gross,
    required this.withholding,
    required this.onTap,
  });

  final String date;
  final String asset;
  final String gross;
  final String withholding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = context.theme.colors.mutedForeground;
    return FTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
        child: Row(
          children: [
            Text(date, style: TextStyle(color: muted)),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(asset, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: AppSpacing.s12),
            Flexible(
              child: Text(
                gross,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Flexible(
              child: Text(
                withholding,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForecastCard extends ConsumerWidget {
  const _ForecastCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final forecast = ref.watch(dividendForecast12mProvider);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Row(
        children: [
          Icon(FLucideIcons.chartLine, color: context.theme.colors.primary),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: forecast.when(
              loading: () => const SkeletonBox(width: 180, height: 42),
              error: (error, stackTrace) => _ForecastText(
                title: l10n.dividendCenterForecastTitle,
                subtitle: l10n.dividendCenterForecastUnavailable,
              ),
              data: (projection) {
                final hasForecast = projection.total > Decimal.zero;
                final subtitle = hasForecast
                    ? l10n.dividendCenterForecastSource(
                        _strategyLabel(l10n, _dominantStrategy(projection)),
                      )
                    : l10n.dividendCenterForecastUnavailable;
                return _ForecastText(
                  title: l10n.dividendCenterForecastTitle,
                  value: hasForecast
                      ? formatters.currency(
                          projection.total,
                          code: projection.currency,
                        )
                      : null,
                  subtitle: subtitle,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ForecastText extends StatelessWidget {
  const _ForecastText({
    required this.title,
    required this.subtitle,
    this.value,
  });

  final String title;
  final String subtitle;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: context.theme.typography.sm),
        if (value != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            value!,
            style: context.theme.typography.lg.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s4),
        Text(
          subtitle,
          style: context.theme.typography.xs.copyWith(
            color: context.theme.colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _EmptyDividendState extends StatelessWidget {
  const _EmptyDividendState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Column(
        children: [
          Icon(
            FLucideIcons.banknote,
            size: AppIconSizes.heroLg,
            color: context.theme.colors.primary,
          ),
          const SizedBox(height: AppSpacing.s16),
          Text(
            l10n.dividendCenterEmptyTitle,
            style: context.theme.typography.lg,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            l10n.dividendCenterEmptyBody,
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s16),
          FButton(
            key: const Key('dividend-center-record-cta'),
            onPress: () => context.push(AppRoutes.wealthCorporateAction),
            child: Text(l10n.dividendCenterRecordAction),
          ),
        ],
      ),
    );
  }
}

String _dominantStrategy(ProjectedDividend projection) {
  if (projection.strategyBreakdown.isEmpty) return projection.strategy;
  return projection.strategyBreakdown.entries.reduce((a, b) {
    return a.value >= b.value ? a : b;
  }).key;
}

String _strategyLabel(AppLocalizations l10n, String strategy) {
  return switch (strategy) {
    'declared' => l10n.dividendForecastStrategyDeclared,
    'dps' => l10n.dividendForecastStrategyDps,
    'ttm' => l10n.dividendForecastStrategyTtm,
    'composite' => l10n.dividendForecastStrategyComposite,
    _ => l10n.dividendForecastStrategyUnknown,
  };
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: context.theme.typography.md.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: context.theme.typography.xs.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
      ],
    );
  }
}
