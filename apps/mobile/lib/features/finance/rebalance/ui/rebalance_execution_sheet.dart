import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../home/ui/asset_category_visuals.dart';
import '../domain/rebalance_models.dart';

Future<bool?> showRebalanceExecutionSheet({
  required BuildContext context,
  required RebalancePlan plan,
}) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<bool>(
    context: context,
    title: l10n.rebalanceExecutionSheetTitle,
    subtitle: l10n.rebalanceExecutionSheetSubtitle(plan.trades.length),
    maxHeightFactor: 0.92,
    footer: Builder(
      builder: (footerContext) => AppSheetFooter(
        cancelLabel: l10n.commonCancel,
        submitLabel: l10n.rebalanceExecutionCreateDrafts,
        onCancel: () => Navigator.of(footerContext).pop(false),
        onSubmit: () => Navigator.of(footerContext).pop(true),
      ),
    ),
    builder: (_) => RebalanceExecutionSheet(plan: plan),
  );
}

class RebalanceExecutionSheet extends StatelessWidget {
  const RebalanceExecutionSheet({super.key, required this.plan});

  final RebalancePlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final trade in plan.trades) _ExecutionTradeRow(trade: trade),
        const SizedBox(height: AppSpacing.s8),
        const FDivider(),
        const SizedBox(height: AppSpacing.s8),
        _MoneySummaryRow(
          label: l10n.rebalanceEstimatedFees,
          amount: plan.estimatedFees.amount.toDouble(),
          currencyCode: plan.estimatedFees.currency,
        ),
        const SizedBox(height: AppSpacing.s8),
        _MoneySummaryRow(
          label: l10n.rebalanceEstimatedTaxes,
          amount: plan.estimatedTaxes.amount.toDouble(),
          currencyCode: plan.estimatedTaxes.currency,
        ),
      ],
    );
  }
}

class _ExecutionTradeRow extends StatelessWidget {
  const _ExecutionTradeRow({required this.trade});

  final SuggestedTrade trade;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isBuy = trade.isBuy;
    final directionLabel = isBuy ? l10n.rebalanceBuy : l10n.rebalanceSell;
    final color = isBuy
        ? context.theme.colors.primary
        : context.theme.colors.mutedForeground;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadius.xxs),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.theme.colors.foreground.withValues(
                alpha: AppOpacity.whisper,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              AssetCategoryVisuals.icon(trade.category),
              color: context.theme.colors.mutedForeground,
              size: AppIconSizes.h18,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$directionLabel ${_tradeTargetLabel(l10n, trade)}',
                  style: context.theme.typography.body.sm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  trade.isAssetTarget
                      ? AssetCategoryVisuals.label(l10n, trade.category)
                      : l10n.rebalanceExecutionTradeValue,
                  style: context.captionStyle,
                ),
              ],
            ),
          ),
          AnimatedMoneyText(
            amount: trade.amount.amount.toDouble(),
            currencyCode: trade.amount.currency,
            compact: true,
            showSign: false,
            style: context.labelStyle,
          ),
        ],
      ),
    );
  }
}

String _tradeTargetLabel(AppLocalizations l10n, SuggestedTrade trade) =>
    trade.targetLabel ?? AssetCategoryVisuals.label(l10n, trade.category);

class _MoneySummaryRow extends StatelessWidget {
  const _MoneySummaryRow({
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
      children: [
        Expanded(child: Text(label, style: context.captionStyle)),
        AnimatedMoneyText(
          amount: amount,
          currencyCode: currencyCode,
          compact: true,
          style: context.captionLabelStyle,
        ),
      ],
    );
  }
}
