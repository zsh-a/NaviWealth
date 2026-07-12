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
    final metricsAsync = ref.watch(dashboardHeaderMetricsProvider);
    final amountsHidden = ref.watch(_financeAmountsHiddenProvider);
    final privacyLabel = amountsHidden
        ? l10n.financePrivacyShowAmountsTooltip
        : l10n.financePrivacyHideAmountsTooltip;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      level: SoftCardLevel.hero,
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
                      ref.read(_financeAmountsHiddenProvider.notifier).state =
                          !amountsHidden;
                    },
                    child: Icon(
                      amountsHidden ? FLucideIcons.eyeClosed : FLucideIcons.eye,
                      size: AppIconSizes.md,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          // Cap dynamic-text scaling on the 32dp hero number so users on
          // 200% system font size don't blow the card out of its row.
          // FittedBox handles long currency strings (¥123,456,789.00)
          // by scaling glyphs down to fit the card's content rect.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
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
                  style: TypographyTokens.numericDisplay,
                  showSign: value != null && value < 0,
                ),
              ),
            ),
          ),
          if (hasData) ...[
            const SizedBox(height: AppSpacing.s6),
            _DeltaMetricsRow(metrics: metricsAsync),
          ],
          const SizedBox(height: AppSpacing.s6),
          // Assets / liabilities breakdown. Uses the same currency
          // formatting (symbol + grouping) as the hero number and
          // mirrors the Accounts-hub net-worth card, so money reads the
          // same everywhere instead of a raw "123456 (CNY)" string.
          DefaultTextStyle.merge(
            style: context.captionStyle,
            child: hasData
                ? Wrap(
                    spacing: AppSpacing.s6,
                    runSpacing: AppSpacing.s4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _NetWorthBreakdownItem(
                        label: l10n.dashboardNetWorthAssetsLabel,
                        amount: snapshot.totalAssets.amount.toDouble(),
                        currencyCode: snapshot.baseCurrency,
                      ),
                      const Text('·'),
                      _NetWorthBreakdownItem(
                        label: l10n.dashboardNetWorthLiabilitiesLabel,
                        amount: snapshot.totalLiabilities.amount.toDouble(),
                        currencyCode: snapshot.baseCurrency,
                      ),
                    ],
                  )
                : Text(l10n.homeNetWorthSubtitle(snapshot.baseCurrency)),
          ),
          const _ValuationStatusLine(),
        ],
      ),
    );
  }
}

class _NetWorthBreakdownItem extends StatelessWidget {
  const _NetWorthBreakdownItem({
    required this.label,
    required this.amount,
    required this.currencyCode,
  });

  final String label;
  final double amount;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label),
        const SizedBox(width: AppSpacing.s4),
        MoneyText(
          amount: amount,
          currencyCode: currencyCode,
          compact: true,
          fractionDigits: 0,
          style: context.captionStyle,
        ),
      ],
    );
  }
}

class _ValuationStatusLine extends ConsumerWidget {
  const _ValuationStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now =
        ref.watch(_valuationStatusTickerProvider).value ?? DateTime.now();
    final priceEvent = ref.watch(priceSyncStatusEventStreamProvider).value;
    final syncEvent = ref.watch(syncStatusEventStreamProvider).value;

    final String? label;
    final bool active;
    if (priceEvent?.status == PriceSyncStatus.syncing) {
      label = l10n.dashboardValuationUpdating;
      active = true;
    } else if (syncEvent?.status == SyncStatus.syncing) {
      label = l10n.dashboardLedgerSyncing;
      active = true;
    } else if (_isRecent(now, priceEvent?.lastSuccessAt)) {
      label = l10n.dashboardValuationUpdated;
      active = false;
    } else {
      return const SizedBox.shrink();
    }

    final colors = context.theme.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active)
            const SizedBox(
              width: AppSpacing.s12,
              height: AppSpacing.s12,
              child: FCircularProgress(),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: AppSpacing.s8),
          Flexible(child: Text(label, style: context.captionMediumStyle)),
        ],
      ),
    );
  }

  bool _isRecent(DateTime now, DateTime? timestamp) {
    if (timestamp == null) return false;
    final age = now.difference(timestamp);
    return !age.isNegative && age < const Duration(minutes: 2);
  }
}

/// Today / MTD / YTD strip rendered under the hero net-worth number.
class _DeltaMetricsRow extends StatelessWidget {
  const _DeltaMetricsRow({required this.metrics});

  final AsyncValue<DashboardHeaderMetrics> metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return metrics.when(
      loading: () => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(width: 60, height: 14, radius: 4),
          SizedBox(width: AppSpacing.s16),
          SkeletonBox(width: 60, height: 14, radius: 4),
          SizedBox(width: AppSpacing.s16),
          SkeletonBox(width: 60, height: 14, radius: 4),
        ],
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (m) {
        return Wrap(
          spacing: AppSpacing.s16,
          runSpacing: AppSpacing.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetricCell(
              label: l10n.dashboardHeaderDeltaTodayLabel,
              child: DeltaText(
                value: m.dailyChange.amount.toDouble(),
                format: DeltaFormat.currency,
                currencyCode: m.baseCurrency,
              ),
            ),
            _MetricCell(
              label: l10n.dashboardHeaderDeltaMonthLabel,
              child: m.monthlyChangePct != null && m.monthlyChangePct!.isFinite
                  ? DeltaChip(
                      value: m.monthlyChangePct! * 100,
                      fractionDigits: 2,
                    )
                  : const DeltaChip(value: null),
            ),
            _MetricCell(
              label: l10n.dashboardHeaderDeltaYtdLabel,
              // Sanity guard: even after the XIRR runaway fix, treat any
              // ratio outside ±100 (i.e. ±10000%) as numerically
              // meaningless and show an unavailable value. This keeps
              // incomparable currency fallbacks from repeating across
              // every period in the hero.
              child: DeltaText.percentFromRatio(
                ratio: _isSaneRatio(m.ytdChangePct) ? m.ytdChangePct : null,
                fractionDigits: 2,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// `true` when [ratio] is non-null, finite, and within ±100 (±10000%).
/// Anything outside that band is almost certainly a numerical artifact
/// upstream — the dashboard hero falls through to the bounded
/// currency-delta representation instead.
bool _isSaneRatio(double? ratio) {
  if (ratio == null) return false;
  if (!ratio.isFinite) return false;
  return ratio.abs() < 100;
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: context.microCaptionStyle),
        const SizedBox(width: AppSpacing.s4),
        child,
      ],
    );
  }
}
