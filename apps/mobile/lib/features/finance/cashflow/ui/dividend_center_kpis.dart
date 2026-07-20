part of 'dividend_center_page.dart';

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
        label: l10n.dividendCenterMetricTtmNet,
        value: formatters.currency(
          snapshot.ttmNet,
          code: snapshot.baseCurrency,
        ),
        caption: snapshot.ttmNetRetentionRatio == null
            ? null
            : l10n.dividendCenterMetricTtmNetCaption(
                formatters.percent(snapshot.ttmNetRetentionRatio!),
              ),
      ),
      _MetricCard(
        label: l10n.dividendCenterMetricYoy,
        value: snapshot.yearOverYearRatio == null
            ? l10n.commonNotAvailable
            : formatters.signedPercent(snapshot.yearOverYearRatio!),
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
  const _MetricCard({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return SoftCard.raised(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: context.captionLabelStyle.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: TypographyTokens.numericTitle),
          ),
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              caption!,
              style: context.captionStyle.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
