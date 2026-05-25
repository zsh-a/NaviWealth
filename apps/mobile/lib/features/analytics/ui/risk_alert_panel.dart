import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../core/format/providers.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/concentration_risk.dart';

/// Panel showing portfolio concentration-risk alerts.
///
/// Displays a list of alerts sorted by severity, each with a color-coded
/// indicator and a tap-through to the relevant asset detail.
class RiskAlertPanel extends ConsumerWidget {
  const RiskAlertPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(concentrationAlertsProvider);

    return alertsAsync.when(
      data: (alerts) {
        if (alerts.isEmpty) return const SizedBox.shrink();
        return _AlertList(alerts: alerts);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _AlertList extends StatelessWidget {
  const _AlertList({required this.alerts});

  final List<ConcentrationAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              FLucideIcons.shield,
              size: 20,
              color: context.theme.colors.destructive,
            ),
            const SizedBox(width: 8),
            Text(l10n.riskAlertTitle, style: context.theme.typography.md),
            const SizedBox(width: 8),
            _AlertCountBadge(count: alerts.length),
          ],
        ),
        const SizedBox(height: 12),
        FCard.raw(
          child: Column(
            children: [
              for (var i = 0; i < alerts.length; i++) ...[
                if (i > 0) const FDivider(),
                _AlertRow(alert: alerts[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertCountBadge extends StatelessWidget {
  const _AlertCountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: context.theme.typography.xs2.copyWith(
          color: theme.colorScheme.onErrorContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AlertRow extends ConsumerWidget {
  const _AlertRow({required this.alert});

  final ConcentrationAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final formatters = ref.watch(
      appFormattersProvider(Localizations.localeOf(context)),
    );
    final severityColor = _severityColor(alert.severity, theme);
    final dimensionLabel = _dimensionLabel(l10n, alert.dimension);

    return FTile(
      title: Text(_alertTitle(l10n, alert), style: context.theme.typography.sm),
      prefix: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: severityColor, shape: BoxShape.circle),
      ),
      subtitle: Text(
        l10n.riskAlertThresholdBreached(
          dimensionLabel,
          formatters.percent(alert.threshold, decimalDigits: 0),
        ),
        style: context.theme.typography.xs.copyWith(
          color: context.theme.colors.mutedForeground,
        ),
      ),
      suffix: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              formatters.percent(alert.weight, decimalDigits: 1),
              style: context.theme.typography.sm.copyWith(
                color: severityColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              formatters.currency(alert.valueInBase, code: _baseCurrency(ref)),
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      onPress: alert.assetIds.length == 1
          ? () => context.goNamed(
              AppRouteNames.wealthAssetDetail,
              pathParameters: {'assetId': alert.assetIds.first},
            )
          : null,
    );
  }

  String _baseCurrency(WidgetRef ref) =>
      ref.read(analyticsBaseCurrencyProvider);
}

String _alertTitle(AppLocalizations l10n, ConcentrationAlert alert) {
  switch (alert.dimension) {
    case RiskDimension.asset:
      return l10n.riskAlertAssetTitle(alert.label);
    case RiskDimension.sector:
      return l10n.riskAlertSectorTitle(alert.label);
    case RiskDimension.region:
      return l10n.riskAlertRegionTitle(alert.label);
    case RiskDimension.currency:
      return l10n.riskAlertCurrencyTitle(alert.label);
  }
}

String _dimensionLabel(AppLocalizations l10n, RiskDimension dim) {
  switch (dim) {
    case RiskDimension.asset:
      return l10n.riskDimensionAsset;
    case RiskDimension.sector:
      return l10n.riskDimensionSector;
    case RiskDimension.region:
      return l10n.riskDimensionRegion;
    case RiskDimension.currency:
      return l10n.riskDimensionCurrency;
  }
}

Color _severityColor(RiskSeverity severity, ThemeData theme) {
  return switch (severity) {
    RiskSeverity.warning => theme.colorScheme.tertiary,
    RiskSeverity.critical => theme.colorScheme.error,
  };
}
