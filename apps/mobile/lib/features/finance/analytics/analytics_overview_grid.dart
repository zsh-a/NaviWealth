part of 'analytics_page.dart';

class _AnalyticsOverviewGrid extends ConsumerWidget {
  const _AnalyticsOverviewGrid({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(dashboardSnapshotProvider);
    final header = ref.watch(dashboardHeaderMetricsProvider);
    final cashFlow = ref.watch(
      cashFlowSummaryProvider(
        const CashFlowSummaryRequest(period: CashFlowPeriod.month),
      ),
    );
    final fire = ref.watch(fireStateProvider);

    return GridView.count(
      crossAxisCount: isWide ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.s12,
      crossAxisSpacing: AppSpacing.s12,
      childAspectRatio: isWide ? 1.8 : 1.2,
      children: [
        _OverviewMetricCard(
          icon: Icons.account_balance_wallet_outlined,
          label: l10n.analyticsOverviewNetWorth,
          child: snapshot.when(
            loading: () => const _OverviewSkeleton(),
            error: (_, _) => const _OverviewUnavailable(),
            data: (s) => MoneyText(
              amount: s.netWorth.amount.toDouble(),
              currencyCode: s.baseCurrency,
              compact: true,
              style: context.theme.typography.body.lg,
            ),
          ),
        ),
        _OverviewMetricCard(
          icon: Icons.trending_up,
          label: l10n.analyticsOverviewMonthlyChange,
          child: header.when(
            loading: () => const _OverviewSkeleton(),
            error: (_, _) => const _OverviewUnavailable(),
            data: (metrics) {
              final formatters = ref.watch(
                appFormattersProvider(Localizations.localeOf(context)),
              );
              final pct = metrics.monthlyChangePct;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SignedMoneyText(
                    amount: metrics.monthlyChange.amount,
                    unit: metrics.baseCurrency,
                    formatters: formatters,
                    style: context.theme.typography.body.lg,
                  ),
                  if (pct != null)
                    Text(
                      formatters.percent(pct, decimalDigits: 1),
                      style: context.captionStyle,
                    ),
                ],
              );
            },
          ),
        ),
        _OverviewMetricCard(
          icon: Icons.payments_outlined,
          label: l10n.analyticsOverviewCashFlow,
          child: cashFlow.when(
            loading: () => const _OverviewSkeleton(),
            error: (_, _) => const _OverviewUnavailable(),
            data: (summary) {
              final formatters = ref.watch(
                appFormattersProvider(Localizations.localeOf(context)),
              );
              return SignedMoneyText(
                amount: summary.totalInBase.amount,
                unit: summary.baseCurrency,
                formatters: formatters,
                style: context.theme.typography.body.lg,
              );
            },
          ),
        ),
        _OverviewMetricCard(
          icon: Icons.flag_outlined,
          label: l10n.analyticsOverviewFireEta,
          child: fire.when(
            loading: () => const _OverviewSkeleton(),
            error: (_, _) => const _OverviewUnavailable(),
            data: (state) {
              if (!state.isConfigured) {
                return Text(
                  l10n.analyticsOverviewFireNotConfigured,
                  style: context.theme.typography.body.sm,
                );
              }
              final months = state.fireEtaMonths;
              return Text(
                months == null
                    ? l10n.analyticsOverviewUnavailable
                    : l10n.analyticsOverviewFireEtaMonths(months),
                style: context.theme.typography.body.lg,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OverviewMetricCard extends StatelessWidget {
  const _OverviewMetricCard({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: AppIconSizes.sm, color: colors.primary),
              const SizedBox(width: AppSpacing.s6),
              Expanded(
                child: Text(
                  label,
                  style: context.captionStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}

class _OverviewSkeleton extends StatelessWidget {
  const _OverviewSkeleton();

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).analyticsOverviewUnavailable,
      style: context.theme.typography.body.lg,
    );
  }
}

class _OverviewUnavailable extends StatelessWidget {
  const _OverviewUnavailable();

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).analyticsOverviewUnavailable,
      style: context.theme.typography.body.lg,
    );
  }
}
