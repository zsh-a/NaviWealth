part of 'portfolio_hub_page.dart';

class _EngineExposureSection extends ConsumerWidget {
  const _EngineExposureSection({required this.baseCurrency});

  final String baseCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final insightsAsync = ref.watch(portfolioHubInsightsProvider);
    return insightsAsync.whenOrLoading(
      context: context,
      skipLoadingOnReload: true,
      onRetry: () => ref.read(portfolioHubInsightsProvider.notifier).refresh(),
      data: (insights) {
        final cards = [
          _RealizedPnlCard(insights: insights, baseCurrency: baseCurrency),
          _DividendForecastCard(
            forecast: insights.dividendForecast,
            baseCurrency: baseCurrency,
          ),
          _EventTimelineCard(
            dividendEvents: insights.dividendEvents,
            corporateActions: insights.corporateActions,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.portfolioHubEnginesTitle,
              style: context.theme.typography.body.lg,
            ),
            const SizedBox(height: AppSpacing.s10),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 860) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < cards.length; i++) ...[
                          if (i != 0) const SizedBox(width: AppSpacing.s12),
                          Expanded(child: cards[i]),
                        ],
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i != 0) const SizedBox(height: AppSpacing.s10),
                      cards[i],
                    ],
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _RealizedPnlCard extends ConsumerWidget {
  const _RealizedPnlCard({required this.insights, required this.baseCurrency});

  final PortfolioHubInsightsState insights;
  final String baseCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final rows = insights.realizedPnl.take(3).toList();
    final total = _sum(insights.realizedPnl.map((row) => row.gain));
    return _EngineCard(
      title: l10n.portfolioHubRealizedPnlTitle,
      trailing: l10n.portfolioHubRealizedPnlCount(insights.realizedPnl.length),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedMoneyText(
            amount: total.toDouble(),
            currencyCode: baseCurrency,
            showSign: true,
            style: context.strongTitleStyle,
          ),
          const SizedBox(height: AppSpacing.s10),
          if (rows.isEmpty)
            _MutedText(l10n.portfolioHubRealizedPnlEmpty)
          else
            for (final row in rows) ...[
              _TwoLineAmountRow(
                title: _assetCode(row.assetId),
                subtitle: l10n.portfolioHubHoldingPeriod(
                  _formatHoldingPeriod(context, row.holdingPeriod),
                ),
                amount: formatters.signedMoney(row.gain, unit: row.currency),
              ),
              if (row != rows.last) const SizedBox(height: AppSpacing.s8),
            ],
        ],
      ),
    );
  }
}

class _DividendForecastCard extends ConsumerWidget {
  const _DividendForecastCard({
    required this.forecast,
    required this.baseCurrency,
  });

  final ProjectedDividend forecast;
  final String baseCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final schedule = forecast.perAsset.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final rows = schedule.take(3).toList();
    return _EngineCard(
      title: l10n.portfolioHubDividendForecastTitle,
      trailing: _strategyLabel(l10n, forecast.strategy),
      onPress: () => context.push(FinanceRoutes.cashflowDividends),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedMoneyText(
            amount: forecast.total.toDouble(),
            currencyCode: forecast.currency.isEmpty
                ? baseCurrency
                : forecast.currency,
            style: context.strongTitleStyle,
          ),
          const SizedBox(height: AppSpacing.s4),
          _MutedText(_confidenceLabel(l10n, forecast.confidence)),
          const SizedBox(height: AppSpacing.s10),
          if (rows.isEmpty)
            _MutedText(l10n.portfolioHubDividendForecastEmpty)
          else
            for (final row in rows) ...[
              _TwoLineAmountRow(
                title: formatters.date(row.key),
                subtitle: l10n.portfolioHubDividendForecastEvent,
                amount: formatters.currency(row.value, code: forecast.currency),
              ),
              if (row != rows.last) const SizedBox(height: AppSpacing.s8),
            ],
        ],
      ),
    );
  }
}

class _EventTimelineCard extends ConsumerWidget {
  const _EventTimelineCard({
    required this.dividendEvents,
    required this.corporateActions,
  });

  final List<DividendCenterEvent> dividendEvents;
  final List<CorporateAction> corporateActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final rows = [
      for (final event in dividendEvents)
        _TimelineRow(
          date: event.event.date,
          title: event.assetLabel,
          subtitle: l10n.corpActionTypeCashDividend,
          detail: formatters.currency(
            event.grossInBase,
            code: event.event.currency,
          ),
        ),
      for (final action in corporateActions)
        _TimelineRow(
          date: action.effectiveDate,
          title: _assetCode(action.assetId),
          subtitle: _corporateActionLabel(l10n, action),
          detail: _corporateActionDetail(formatters, action),
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final visibleRows = rows.take(3).toList();
    return _EngineCard(
      title: l10n.portfolioHubEventTimelineTitle,
      trailing: l10n.portfolioHubEventTimelineCount(rows.length),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (visibleRows.isEmpty)
            _MutedText(l10n.portfolioHubEventTimelineEmpty)
          else
            for (final row in visibleRows) ...[
              _TwoLineAmountRow(
                title: row.title,
                subtitle: '${formatters.date(row.date)} - ${row.subtitle}',
                amount: row.detail,
              ),
              if (row != visibleRows.last)
                const SizedBox(height: AppSpacing.s8),
            ],
        ],
      ),
    );
  }
}

class _TimelineRow {
  const _TimelineRow({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.detail,
  });

  final DateTime date;
  final String title;
  final String subtitle;
  final String detail;
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({
    required this.title,
    required this.trailing,
    required this.child,
    this.onPress,
  });

  final String title;
  final String trailing;
  final Widget child;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    return SoftCard.flat(
      onPress: onPress,
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: context.labelStyle)),
              const SizedBox(width: AppSpacing.s8),
              Text(trailing, style: context.captionStyle),
              if (onPress != null) ...[
                const SizedBox(width: AppSpacing.s4),
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.sm,
                  color: context.theme.colors.mutedForeground,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          child,
        ],
      ),
    );
  }
}

class _TwoLineAmountRow extends StatelessWidget {
  const _TwoLineAmountRow({
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  final String title;
  final String subtitle;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TitleSubtitle(title: title, subtitle: subtitle),
        ),
        const SizedBox(width: AppSpacing.s12),
        Text(
          amount,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.captionLabelStyle,
        ),
      ],
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: context.captionStyle);
  }
}
