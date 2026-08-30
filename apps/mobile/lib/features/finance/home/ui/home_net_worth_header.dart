part of 'home_page.dart';

class _NetWorthHeader extends ConsumerWidget {
  const _NetWorthHeader({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formatters = context.formatters(ref);
    final hasData = !snapshot.isEmpty;
    final value = hasData ? snapshot.netWorth.amount.toDouble() : null;
    final dailyChangeAsync = ref.watch(dashboardDailyChangeProvider);
    final amountsHidden = ref.watch(financeAmountsHiddenProvider);
    final privacyLabel = amountsHidden
        ? l10n.financePrivacyShowAmountsTooltip
        : l10n.financePrivacyHideAmountsTooltip;

    // Number + day delta only — full trend chart lives on Wealth.
    // Scroll-linked collapse keeps the Today stage from dominating long feeds.
    return AppCollapsingStage(
      child: SoftCard.hero(
        // SoftCard owns select haptics; keep navigation as plain side-effect.
        onPress: () =>
            StatefulNavigationShell.of(context)
                .goBranch(FinanceShellTab.wealth.index, initialLocation: true),
        padding: AppPageRhythm.heroPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.homeNetWorthTitle,
                    style: context.mutedLabelStyle,
                  ),
                ),
                Semantics(
                  button: true,
                  label: privacyLabel,
                  child: FTooltip(
                    tipBuilder: (_, _) => Text(privacyLabel),
                    child: FButton.icon(
                      variant: FButtonVariant.ghost,
                      onPress: () {
                        ref
                            .read(financeAmountsHiddenProvider.notifier)
                            .toggle();
                      },
                      child: Icon(
                        amountsHidden
                            ? FLucideIcons.eyeClosed
                            : FLucideIcons.eye,
                        size: AppIconSizes.md,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppPageRhythm.row),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.25,
              child: Semantics(
                label: amountsHidden
                    ? '${l10n.homeNetWorthTitle} ${AmountPrivacyScope.hiddenSemanticsLabelOf(context)}'
                    : '${l10n.homeNetWorthTitle} ${formatters.currency(snapshot.netWorth.amount, code: snapshot.baseCurrency)}',
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: AnimatedMoneyText(
                    amount: value,
                    currencyCode: snapshot.baseCurrency,
                    style: TypographyTokens.displayLarge,
                    showSign: value != null && value < 0,
                  ),
                ),
              ),
            ),
            if (hasData) ...[
              const SizedBox(height: AppPageRhythm.row),
              _TodayDeltaMetric(dailyChange: dailyChangeAsync),
            ],
            if (!hasData) ...[
              const SizedBox(height: AppPageRhythm.row),
              Text(
                l10n.homeNetWorthSubtitle(snapshot.baseCurrency),
                style: context.captionStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodayDeltaMetric extends StatelessWidget {
  const _TodayDeltaMetric({required this.dailyChange});

  final AsyncValue<DashboardDailyChange> dailyChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return dailyChange.when(
      loading: () => const SkeletonBox(width: 96, height: 14, radius: 4),
      // Keep a visible em-dash on failure (the `_ValueDash` precedent)
      // instead of silently dropping the hero metric.
      error: (_, _) => Text('—', style: context.captionStyle),
      data: (daily) => daily.change == null
          ? const SizedBox.shrink()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.dashboardHeaderDeltaTodayLabel,
                  style: context.captionStyle,
                ),
                const SizedBox(width: AppSpacing.s6),
                DeltaText(
                  value: daily.change!.amount.toDouble(),
                  format: DeltaFormat.currency,
                  currencyCode: daily.baseCurrency,
                ),
              ],
            ),
    );
  }
}
