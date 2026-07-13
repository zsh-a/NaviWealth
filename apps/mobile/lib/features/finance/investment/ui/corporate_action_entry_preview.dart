part of 'corporate_action_entry_page.dart';

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({super.key, required this.preview, required this.l10n});

  final CorporateActionPreview preview;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final dividend = preview.cashDividend;
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.corpActionPreviewHeading,
            style: context.theme.typography.body.md,
          ),
          const SizedBox(height: AppSpacing.s12),
          if (dividend != null) ...[
            _kv(l10n.corpActionPreviewSharesOnRecord, '${dividend.shareCount}'),
            _kv(
              l10n.corpActionPreviewGross,
              _fmtCurrency(dividend.grossAmount, dividend.currency),
            ),
            _kv(
              l10n.corpActionPreviewTax,
              _fmtCurrency(dividend.withholdingTax, dividend.currency),
            ),
            _kv(
              l10n.corpActionPreviewNet,
              _fmtCurrency(dividend.netAmount, dividend.currency),
            ),
          ] else if (preview.action is CashDividendAction)
            Text(l10n.corpActionNoEligibleHolding),
          if (preview.cashFlow != Decimal.zero)
            _kv(
              l10n.corpActionPreviewCashFlow,
              _fmtCurrency(preview.cashFlow, preview.cashFlowCurrency),
            ),
          for (final delta in preview.lotDeltas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
              child: Text(
                l10n.corpActionPreviewLotChange(
                  delta.before.id,
                  '${delta.before.remainingQuantity}',
                  '${delta.after.remainingQuantity}',
                  '${delta.before.costPerUnit}',
                  '${delta.after.costPerUnit}',
                ),
              ),
            ),
          for (final newLot in preview.newLots)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
              child: Text(
                l10n.corpActionPreviewNewLot(
                  '${newLot.originalQuantity}',
                  '${newLot.costPerUnit}',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
    child: Row(
      children: [
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: AppSpacing.s12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  static String _fmtCurrency(Decimal amount, String currency) {
    return NumberFormat.currency(
      name: currency,
      symbol: _currencySymbol(currency),
    ).format(amount.toDouble());
  }

  static String _currencySymbol(String code) =>
      AppFormatters.currencyGlyph(code);
}
