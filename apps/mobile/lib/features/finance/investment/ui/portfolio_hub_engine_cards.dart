part of 'portfolio_hub_page.dart';

class _PortfolioInsightsSection extends ConsumerWidget {
  const _PortfolioInsightsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final insightsAsync = ref.watch(portfolioHubInsightsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PortfolioSectionTitle(title: l10n.portfolioHubIncomeEventsTitle),
        insightsAsync.whenOrLoading(
          context: context,
          skipLoadingOnReload: true,
          onRetry: () =>
              ref.read(portfolioHubInsightsProvider.notifier).refresh(),
          data: (insights) {
            final cards = [
              _RealizedPnlCard(insights: insights),
              _DividendForecastCard(forecast: insights.dividendForecast),
              _EventTimelineCard(
                dividendEvents: insights.dividendEvents,
                corporateActions: insights.corporateActions,
              ),
            ];
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >=
                    1000 * MediaQuery.textScalerOf(context).scale(1)) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < cards.length; i++) ...[
                        if (i != 0) const SizedBox(width: AppSpacing.s12),
                        Expanded(child: cards[i]),
                      ],
                    ],
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
            );
          },
        ),
      ],
    );
  }
}

class _RealizedPnlCard extends ConsumerWidget {
  const _RealizedPnlCard({required this.insights});

  final PortfolioHubInsightsState insights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final rows = [...insights.realizedPnl]
      ..sort((a, b) => b.realizedAt.compareTo(a.realizedAt));
    // Realized gains are denominated in each lot's currency, not the hub base.
    final totals = <String, Decimal>{};
    for (final row in rows) {
      totals.update(
        row.currency,
        (value) => value + row.gain,
        ifAbsent: () => row.gain,
      );
    }
    final currencies = totals.keys.toList()..sort();
    return _EngineCard(
      title: l10n.portfolioHubRealizedPnlTitle,
      trailing: l10n.portfolioHubRealizedPnlCount(insights.realizedPnl.length),
      onPress: rows.isEmpty
          ? null
          : () => _showPortfolioDetailSheet<void>(
              context: context,
              title: l10n.portfolioHubRealizedPnlTitle,
              builder: (_) => _InsightDetailList(
                children: [
                  for (final row in rows)
                    _TwoLineAmountRow(
                      title: _assetCode(row.assetId),
                      subtitle:
                          '${formatters.date(row.realizedAt)} · ${l10n.portfolioHubHoldingPeriod(_formatHoldingPeriod(context, row.holdingPeriod))}',
                      amount: formatters.signedMoney(
                        row.gain,
                        unit: row.currency,
                      ),
                    ),
                ],
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            _MutedText(l10n.portfolioHubRealizedPnlEmpty)
          else
            for (final currency in currencies)
              AnimatedMoneyText(
                amount: totals[currency]!.toDouble(),
                currencyCode: currency,
                symbolStyle: currencies.length > 1
                    ? MoneySymbolStyle.isoCode
                    : MoneySymbolStyle.symbol,
                showSign: true,
                style: context.strongTitleStyle,
              ),
        ],
      ),
    );
  }
}

class _DividendForecastCard extends ConsumerWidget {
  const _DividendForecastCard({required this.forecast});

  final ProjectedDividend forecast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final schedule = forecast.perAsset.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final currency = forecast.currency.isEmpty
        ? ref.watch(holdingBaseCurrencyProvider)
        : forecast.currency;
    return _EngineCard(
      title: l10n.portfolioHubDividendForecastTitle,
      trailing: _strategyLabel(l10n, forecast.strategy),
      onPress: () async {
        final openCenter = await _showPortfolioDetailSheet<bool>(
          context: context,
          title: l10n.portfolioHubDividendForecastTitle,
          subtitle: _confidenceLabel(l10n, forecast.confidence),
          footer: Builder(
            builder: (sheetContext) => FButton(
              variant: FButtonVariant.outline,
              onPress: () => Navigator.of(sheetContext).pop(true),
              child: Text(l10n.dividendCenterTitle),
            ),
          ),
          builder: (_) => schedule.isEmpty
              ? _MutedText(l10n.portfolioHubDividendForecastEmpty)
              : _InsightDetailList(
                  children: [
                    for (final row in schedule)
                      _TwoLineAmountRow(
                        title: formatters.date(row.key),
                        subtitle: l10n.portfolioHubDividendForecastEvent,
                        amount: formatters.currency(row.value, code: currency),
                      ),
                  ],
                ),
        );
        if (context.mounted && openCenter == true) {
          await context.push(FinanceRoutes.cashflowDividends);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedMoneyText(
            amount: forecast.total.toDouble(),
            currencyCode: currency,
            style: context.strongTitleStyle,
          ),
          const SizedBox(height: AppSpacing.s4),
          _MutedText(_confidenceLabel(l10n, forecast.confidence)),
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
            event.event.originalAmount,
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
    final visibleRows = rows.take(1).toList();
    return _EngineCard(
      title: l10n.portfolioHubEventTimelineTitle,
      trailing: l10n.portfolioHubEventTimelineCount(rows.length),
      onPress: rows.isEmpty
          ? null
          : () => _showPortfolioDetailSheet<void>(
              context: context,
              title: l10n.portfolioHubEventTimelineTitle,
              builder: (_) => _InsightDetailList(
                children: [
                  for (final row in rows)
                    _TwoLineAmountRow(
                      title: row.title,
                      subtitle:
                          '${formatters.date(row.date)} · ${row.subtitle}',
                      amount: row.detail,
                    ),
                ],
              ),
            ),
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
              Flexible(
                fit: FlexFit.tight,
                child: Text(
                  trailing,
                  style: context.captionStyle,
                  textAlign: TextAlign.end,
                ),
              ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final amountText = Text(amount, style: context.captionLabelStyle);
        if (constraints.maxWidth < 400 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.labelStyle),
              const SizedBox(height: AppSpacing.s4),
              Text(subtitle, style: context.captionStyle),
              const SizedBox(height: AppSpacing.s4),
              amountText,
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: _TitleSubtitle(title: title, subtitle: subtitle),
            ),
            const SizedBox(width: AppSpacing.s12),
            Flexible(child: amountText),
          ],
        );
      },
    );
  }
}

class _InsightDetailList extends StatelessWidget {
  const _InsightDetailList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s12),
            child: AppGroupedDivider(),
          ),
        children[index],
      ],
    ],
  );
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: context.captionStyle);
  }
}
