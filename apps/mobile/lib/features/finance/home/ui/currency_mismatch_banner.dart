import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:naviwealth/core/shell/settings_route_paths.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../market/domain/price_confidence.dart';
import '../domain/dashboard_models.dart';

/// Compact valuation provenance shown beside every non-empty net-worth view.
///
/// Missing FX remains the highest-severity state because rows were excluded
/// from totals. Stale and estimated prices are warnings. Fresh, delayed,
/// daily-close and manual valuations still show their as-of time so users can
/// tell what the headline number actually represents.
class ValuationTrustNotice extends StatelessWidget {
  const ValuationTrustNotice({required this.snapshot, super.key});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.isEmpty && snapshot.currencyMismatches.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final quality = _qualityLabel(l10n, snapshot.confidenceFloor);
    final asOf = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_Hm().format(snapshot.asOf.toLocal());
    final hasMissingFx = snapshot.currencyMismatches.isNotEmpty;
    final isLowTrust =
        snapshot.staleHoldingCount > 0 ||
        snapshot.confidenceFloor == PriceConfidence.stale ||
        snapshot.confidenceFloor == PriceConfidence.estimated;
    final message = hasMissingFx
        ? l10n.dashboardValuationTrustMissingFx(
            snapshot.currencyMismatches.length,
            snapshot.baseCurrency,
          )
        : isLowTrust
        ? l10n.dashboardValuationTrustWarning(
            snapshot.staleHoldingCount,
            quality,
            asOf,
          )
        : l10n.dashboardValuationTrustReady(quality, asOf);
    return AppStatusBanner(
      kind: hasMissingFx
          ? AppStatusKind.error
          : isLowTrust
          ? AppStatusKind.warning
          : AppStatusKind.success,
      message: message,
      compact: true,
      onPress: () => _showDetails(context, quality, asOf),
      semanticLabel: l10n.dashboardValuationTrustAction,
      action: Text(
        l10n.dashboardValuationTrustAction,
        style: context.labelStyle,
      ),
    );
  }

  void _showDetails(BuildContext context, String quality, String asOf) {
    final l10n = AppLocalizations.of(context);
    showAppSheet<void>(
      context: context,
      title: l10n.dashboardValuationTrustSheetTitle,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTile(
            title: Text(l10n.dashboardValuationTrustQuality(quality)),
            prefix: const Icon(FLucideIcons.shieldCheck),
            subtitle: Text(l10n.dashboardValuationTrustAsOf(asOf)),
          ),
          if (snapshot.staleHoldingCount > 0)
            FTile(
              title: Text(
                l10n.dashboardValuationTrustStale(snapshot.staleHoldingCount),
              ),
              prefix: const Icon(FLucideIcons.triangleAlert),
            ),
          for (final m in snapshot.currencyMismatches)
            FTile(
              title: Text('${m.currency} → ${snapshot.baseCurrency}'),
              prefix: const Icon(FLucideIcons.arrowLeftRight),
              subtitle: Text(m.id),
              suffix: const Icon(FLucideIcons.chevronRight),
              onPress: () {
                Navigator.of(ctx).pop();
                context.goNamed(SettingsRouteNames.fxRates);
              },
            ),
        ],
      ),
    );
  }

  String _qualityLabel(AppLocalizations l10n, PriceConfidence? confidence) =>
      switch (confidence) {
        PriceConfidence.realTime => l10n.dashboardValuationQualityRealTime,
        PriceConfidence.delayed => l10n.dashboardValuationQualityDelayed,
        PriceConfidence.dailyClose => l10n.dashboardValuationQualityDailyClose,
        PriceConfidence.manual => l10n.dashboardValuationQualityManual,
        PriceConfidence.estimated => l10n.dashboardValuationQualityEstimated,
        PriceConfidence.stale => l10n.dashboardValuationQualityStale,
        null => l10n.dashboardValuationQualityManual,
      };
}
