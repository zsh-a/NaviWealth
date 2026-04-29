import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../home/ui/asset_category_visuals.dart';
import '../data/rebalance_providers.dart';
import '../domain/allocation_schemes.dart';
import '../domain/rebalance_models.dart';
import 'deviation_bar.dart';

/// Rebalance page — shows target vs actual allocation, deviation bars,
/// and suggested trades.
class RebalancePage extends ConsumerWidget {
  const RebalancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final plan = ref.watch(rebalancePlanProvider);
    final scheme = ref.watch(selectedSchemeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.rebalanceTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.rebalanceSettingsTooltip,
            onPressed: () => _openSettings(context, ref),
          ),
        ],
      ),
      body: plan == null
          ? _EmptyState()
          : _RebalanceBody(plan: plan, scheme: scheme),
    );
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => const _SettingsSheet(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: Spacing.pageMobile,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.balance, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: Spacing.s12),
            Text(
              l10n.rebalanceEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              l10n.rebalanceEmptyHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RebalanceBody extends StatelessWidget {
  const _RebalanceBody({required this.plan, required this.scheme});

  final RebalancePlan plan;
  final AllocationSchemePreset scheme;

  @override
  Widget build(BuildContext context) {
    final isWide = !Breakpoints.isMobile(MediaQuery.sizeOf(context).width);
    final padding = isWide ? Spacing.pageWide : Spacing.pageMobile;

    final schemeSection = _SchemeSelector(current: scheme);
    final driftSection = _DriftOverview(plan: plan);
    final tradeSection = _TradeList(plan: plan);

    if (isWide) {
      return ListView(
        padding: padding,
        children: [
          schemeSection,
          const SizedBox(height: Spacing.s16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: driftSection),
              const SizedBox(width: Spacing.s16),
              Expanded(child: tradeSection),
            ],
          ),
        ],
      );
    }

    return ListView(
      padding: padding,
      children: [
        schemeSection,
        const SizedBox(height: Spacing.s12),
        driftSection,
        const SizedBox(height: Spacing.s12),
        tradeSection,
      ],
    );
  }
}

class _SchemeSelector extends ConsumerWidget {
  const _SchemeSelector({required this.current});

  final AllocationSchemePreset current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rebalanceSchemeTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.s8),
            Wrap(
              spacing: Spacing.s8,
              children: [
                for (final preset in AllocationSchemePreset.values)
                  ChoiceChip(
                    label: Text(_schemeLabel(l10n, preset)),
                    selected: current == preset,
                    onSelected: (selected) {
                      if (selected) {
                        ref.read(selectedSchemeProvider.notifier).select(preset);
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _schemeLabel(AppLocalizations l10n, AllocationSchemePreset preset) {
    switch (preset) {
      case AllocationSchemePreset.conservative:
        return l10n.rebalanceSchemeConservative;
      case AllocationSchemePreset.balanced:
        return l10n.rebalanceSchemeBalanced;
      case AllocationSchemePreset.aggressive:
        return l10n.rebalanceSchemeAggressive;
      case AllocationSchemePreset.custom:
        return l10n.rebalanceSchemeCustom;
    }
  }
}

class _DriftOverview extends StatelessWidget {
  const _DriftOverview({required this.plan});

  final RebalancePlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceDriftTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (plan.isBalanced)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.s8,
                      vertical: Spacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(Radii.sm),
                    ),
                    child: Text(
                      l10n.rebalanceBalanced,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              l10n.rebalanceOverallDrift(
                '${(plan.driftBeforePct * 100).toStringAsFixed(1)}%',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Spacing.s8),
            for (final drift in plan.drifts)
              DeviationBar(
                label: AssetCategoryVisuals.label(l10n, drift.category),
                actualWeight: drift.actualWeight,
                targetWeight: drift.targetWeight,
                deviation: drift.deviation,
                severity: drift.severity,
              ),
          ],
        ),
      ),
    );
  }
}

class _TradeList extends StatelessWidget {
  const _TradeList({required this.plan});

  final RebalancePlan plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (plan.isBalanced) {
      return Card(
        child: Padding(
          padding: Spacing.card,
          child: Column(
            children: [
              Icon(Icons.check_circle_outline, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: Spacing.s8),
              Text(l10n.rebalanceBalanced, style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rebalanceTradeTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.s8),
            for (final trade in plan.trades) _TradeRow(trade: trade),
            const Divider(height: Spacing.s24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceEstimatedFees,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                MoneyText(
                  amount: plan.estimatedFees.amount.toDouble(),
                  currencyCode: plan.estimatedFees.currency,
                  compact: true,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: Spacing.s4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceEstimatedTaxes,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                MoneyText(
                  amount: plan.estimatedTaxes.amount.toDouble(),
                  currencyCode: plan.estimatedTaxes.currency,
                  compact: true,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: Spacing.s4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.rebalanceDriftAfter,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${(plan.driftAfterPct * 100).toStringAsFixed(1)}%',
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TradeRow extends StatelessWidget {
  const _TradeRow({required this.trade});

  final SuggestedTrade trade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isBuy = trade.isBuy;
    final directionLabel = isBuy ? l10n.rebalanceBuy : l10n.rebalanceSell;
    final directionColor = isBuy
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;
    final icon = AssetCategoryVisuals.icon(trade.category);
    final catLabel = AssetCategoryVisuals.label(l10n, trade.category);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.s4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: directionColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: Spacing.s8),
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: Spacing.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$directionLabel $catLabel',
                  style: theme.textTheme.bodyMedium,
                ),
                if (trade.description != null)
                  Text(
                    trade.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          MoneyText(
            amount: trade.amount.amount.toDouble(),
            currencyCode: trade.amount.currency,
            compact: true,
            showSign: false,
          ),
        ],
      ),
    );
  }
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final warning = ref.watch(warningThresholdProvider);
    final critical = ref.watch(criticalThresholdProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.s16,
          Spacing.s8,
          Spacing.s16,
          Spacing.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rebalanceSettingsTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.s16),
            Text(
              l10n.rebalanceWarningThreshold,
              style: theme.textTheme.bodyMedium,
            ),
            Slider(
              value: warning,
              min: 0.01,
              max: 0.20,
              divisions: 19,
              label: '${(warning * 100).toStringAsFixed(0)}%',
              onChanged: (v) =>
                  ref.read(warningThresholdProvider.notifier).set(v),
            ),
            const SizedBox(height: Spacing.s8),
            Text(
              l10n.rebalanceCriticalThreshold,
              style: theme.textTheme.bodyMedium,
            ),
            Slider(
              value: critical,
              min: 0.05,
              max: 0.30,
              divisions: 25,
              label: '${(critical * 100).toStringAsFixed(0)}%',
              onChanged: (v) =>
                  ref.read(criticalThresholdProvider.notifier).set(v),
            ),
          ],
        ),
      ),
    );
  }
}
