part of '../analytics_page.dart';

class _FireProgressCard extends ConsumerWidget {
  const _FireProgressCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(fireStateProvider);
    return SoftCard(
      borderless: true,
      level: SoftCardLevel.raised,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.analyticsFireProgressTitle,
              style: context.theme.typography.body.md,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              l10n.analyticsFireProgressSubtitle,
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s16),
            async.when(
              loading: () => const SizedBox(
                height: AppChartHeights.card,
                child: Center(child: FCircularProgress()),
              ),
              error: (error, _) => AppEmptyState.error(
                title: l10n.analyticsFireProgressLoadError,
                message: userSafeErrorMessage(context, error),
                icon: FLucideIcons.circleX,
              ),
              data: (state) => _FireProgressContent(state: state),
            ),
          ],
        ),
      ),
    );
  }
}

class _FireProgressContent extends ConsumerWidget {
  const _FireProgressContent({required this.state});

  final FireState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    if (!state.isConfigured) {
      return AppEmptyState(
        icon: FLucideIcons.flag,
        title: l10n.analyticsFireProgressNotConfiguredTitle,
        message: l10n.analyticsFireProgressNotConfiguredBody,
      );
    }

    final target = state.plan.targetNetWorthMoney;
    final progress = target.amount == Decimal.zero
        ? 0.0
        : (state.investableAssets.amount / target.amount)
              .toDecimal(scaleOnInfinitePrecision: 6)
              .toDouble()
              .clamp(0.0, 1.0);
    final eta = state.fireEtaMonths;
    final withdrawal = state.finiteWithdrawalRate;
    final cashMonths = state.cashBucketMonthsRounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FDeterminateProgress(value: progress),
        const SizedBox(height: AppSpacing.s8),
        Text(
          l10n.analyticsFireProgressPercent(
            formatters.percent(progress, decimalDigits: 1),
          ),
          style: context.captionStyle,
        ),
        const SizedBox(height: AppSpacing.s16),
        Wrap(
          spacing: AppSpacing.s16,
          runSpacing: AppSpacing.s8,
          children: [
            _MetricReadout(
              label: l10n.analyticsFireProgressInvestable,
              value: formatters.currency(
                state.investableAssets.amount,
                code: state.baseCurrency,
              ),
            ),
            _MetricReadout(
              label: l10n.analyticsFireProgressTarget,
              value: formatters.currency(target.amount, code: target.currency),
            ),
            _MetricReadout(
              label: l10n.analyticsFireProgressWithdrawalRate,
              value: withdrawal == null
                  ? l10n.analyticsOverviewUnavailable
                  : formatters.percent(withdrawal, decimalDigits: 1),
            ),
            _MetricReadout(
              label: l10n.analyticsFireProgressCashRunway,
              value: cashMonths == null
                  ? l10n.analyticsFireProgressUnlimited
                  : l10n.analyticsFireProgressMonths(cashMonths),
            ),
            _MetricReadout(
              label: l10n.analyticsFireProgressEta,
              value: eta == null
                  ? l10n.analyticsOverviewUnavailable
                  : l10n.analyticsOverviewFireEtaMonths(eta),
            ),
          ],
        ),
      ],
    );
  }
}
