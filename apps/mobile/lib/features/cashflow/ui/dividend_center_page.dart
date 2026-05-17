import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/dividend_center_providers.dart';
import '../domain/dividend_center.dart';

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
            icon: const Icon(Icons.add_card_outlined),
            onPress: () => context.push(AppRoutes.accountCorporateAction),
          ),
        ],
      ),
      childPad: false,
      child: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(error: error),
        data: (data) => _DividendCenterBody(snapshot: data),
      ),
    );
  }
}

class _DividendCenterBody extends StatelessWidget {
  const _DividendCenterBody({required this.snapshot});

  final DividendCenterSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final padding = Breakpoints.isMobile(width)
            ? const EdgeInsets.all(16)
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 24);
        return ListView(
          padding: EdgeInsets.only(
            left: padding.left,
            right: padding.right,
            top: padding.top,
            bottom: padding.bottom + MediaQuery.paddingOf(context).bottom + 16,
          ),
          children: [
            if (snapshot.isEmpty)
              const _EmptyDividendState()
            else ...[
              _KpiGrid(snapshot: snapshot),
              const SizedBox(height: 16),
              _RankingSection(snapshot: snapshot),
              const SizedBox(height: 16),
              const _ForecastStub(),
              const SizedBox(height: 16),
              _TimelineSection(snapshot: snapshot),
            ],
          ],
        );
      },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: columns == 4 ? 1.9 : 1.55,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
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
      padding: const EdgeInsets.all(16),
      borderRadius: 8,
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
          const SizedBox(height: 8),
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
      padding: const EdgeInsets.all(16),
      borderRadius: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(
            title: l10n.dividendCenterHoldingRanking,
            trailing: 'TTM',
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            _RankRow(
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
            if (row != rows.last) const Divider(height: 16),
          ],
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.name,
    required this.amount,
    required this.share,
    required this.yieldOnCost,
    required this.withholding,
  });

  final String name;
  final String amount;
  final String share;
  final String yieldOnCost;
  final String withholding;

  @override
  Widget build(BuildContext context) {
    final muted = context.theme.colors.mutedForeground;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(name, style: context.theme.typography.sm),
        ),
        Expanded(flex: 3, child: Text(amount, textAlign: TextAlign.end)),
        Expanded(flex: 2, child: Text(share, textAlign: TextAlign.end)),
        Expanded(flex: 2, child: Text(yieldOnCost, textAlign: TextAlign.end)),
        Expanded(
          flex: 3,
          child: Text(
            withholding,
            textAlign: TextAlign.end,
            style: TextStyle(color: muted),
          ),
        ),
      ],
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
      padding: const EdgeInsets.all(16),
      borderRadius: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeading(title: l10n.dividendCenterHistoryTimeline),
          const SizedBox(height: 12),
          for (final month in snapshot.months) ...[
            Text(
              formatters.monthYear(month.month),
              style: context.theme.typography.sm.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final event in month.events)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
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
                ),
              ),
            const SizedBox(height: 6),
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
  });

  final String date;
  final String asset;
  final String gross;
  final String withholding;

  @override
  Widget build(BuildContext context) {
    final muted = context.theme.colors.mutedForeground;
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(date, style: TextStyle(color: muted)),
        ),
        Expanded(child: Text(asset)),
        Text(gross),
        const SizedBox(width: 12),
        Text(withholding, style: TextStyle(color: muted)),
      ],
    );
  }
}

class _ForecastStub extends StatelessWidget {
  const _ForecastStub();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 8,
      child: Row(
        children: [
          Icon(Icons.auto_graph_outlined, color: context.theme.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dividendCenterForecastTitle,
                  style: context.theme.typography.sm,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.dividendCenterForecastUnavailable,
                  style: context.theme.typography.xs.copyWith(
                    color: context.theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDividendState extends StatelessWidget {
  const _EmptyDividendState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      padding: const EdgeInsets.all(24),
      borderRadius: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.payments_outlined, color: context.theme.colors.primary),
          const SizedBox(height: 12),
          Text(
            l10n.dividendCenterEmptyTitle,
            style: context.theme.typography.lg,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.dividendCenterEmptyBody,
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 16),
          FButton(
            key: const Key('dividend-center-record-cta'),
            onPress: () => context.push(AppRoutes.accountCorporateAction),
            child: Text(l10n.dividendCenterRecordAction),
          ),
        ],
      ),
    );
  }
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
              fontWeight: FontWeight.w700,
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l10n.dividendCenterLoadError(error.toString())),
      ),
    );
  }
}
