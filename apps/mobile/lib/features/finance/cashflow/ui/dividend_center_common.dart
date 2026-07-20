part of 'dividend_center_page.dart';

/// Surfaces TTM dividend declines that also feed Financial Inbox, so the
/// `/wealth/portfolio/dividends` deep link lands on a real review surface.
class _DividendPolicySection extends StatelessWidget {
  const _DividendPolicySection({required this.rows, this.focusAssetId});

  final List<DividendDeterioration> rows;
  final String? focusAssetId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final criticalCount = rows
        .where((r) => r.severity == DividendDeteriorationSeverity.critical)
        .length;
    return SoftCard.raised(
      borderless: true,
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.trendingDown,
                size: AppIconSizes.h18,
                color: criticalCount > 0
                    ? context.theme.colors.destructive
                    : context.theme.colors.primary,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  l10n.dividendCenterPolicyTitle,
                  style: context.rowTitleStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            l10n.dividendCenterPolicyBody(rows.length),
            style: context.captionStyle,
          ),
          const SizedBox(height: AppSpacing.s12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i != 0) const SizedBox(height: AppSpacing.s8),
            _DividendPolicyRow(
              row: rows[i],
              focused: rows[i].assetId == focusAssetId,
            ),
          ],
        ],
      ),
    );
  }
}

class _DividendPolicyRow extends StatelessWidget {
  const _DividendPolicyRow({required this.row, required this.focused});

  final DividendDeterioration row;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dropPct = (row.dropRatio * 100).toStringAsFixed(0);
    final severity = row.severity == DividendDeteriorationSeverity.critical
        ? l10n.dividendCenterPolicySeverityCritical
        : l10n.dividendCenterPolicySeverityWarning;
    return Container(
      key: ValueKey('dividend-review-${row.assetId}'),
      padding: const EdgeInsets.all(AppSpacing.s6),
      decoration: focused
          ? BoxDecoration(
              color: context.theme.colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.assetLabel, style: context.labelStyle),
                const SizedBox(height: AppSpacing.s2),
                Text(severity, style: context.captionStyle),
              ],
            ),
          ),
          Text(
            l10n.dividendCenterPolicyDropLine(dropPct),
            style: context.captionLabelStyle,
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
    return AppEmptyState(
      icon: FLucideIcons.banknote,
      title: l10n.dividendCenterEmptyTitle,
      message: l10n.dividendCenterEmptyBody,
      action: FButton(
        key: const Key('dividend-center-record-cta'),
        onPress: () => context.push(FinanceRoutes.wealthCorporateAction),
        child: Text(l10n.dividendCenterRecordAction),
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
        Expanded(child: Text(title, style: context.rowTitleStyle)),
        if (trailing != null) Text(trailing!, style: context.captionStyle),
      ],
    );
  }
}
