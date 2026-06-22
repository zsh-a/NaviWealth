import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/dashboard_models.dart';

/// Warning notice shown above the dashboard when one or more holdings were
/// excluded from the totals because no FX rate is available to convert
/// them into the active base currency.
///
/// Silently dropping foreign-currency rows is what shipped before;
/// the notice makes the omission visible so users don't read a stale total
/// as ground truth. Tapping it surfaces the offending holdings (currency
/// + id) so the user can either record the missing rate or fix the
/// holding's currency.
class CurrencyMismatchNotice extends StatelessWidget {
  const CurrencyMismatchNotice({
    required this.mismatches,
    required this.baseCurrency,
    super.key,
  });

  final List<CurrencyMismatch> mismatches;
  final String baseCurrency;

  @override
  Widget build(BuildContext context) {
    final semantic = SemanticColors.of(context);
    if (mismatches.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () => _showDetails(context, mismatches, baseCurrency),
      behavior: HitTestBehavior.opaque,
      child: AppStatusBanner(
        kind: AppStatusKind.error,
        icon: FLucideIcons.triangleAlert,
        message: l10n.dashboardCurrencyMismatchBanner(
          mismatches.length,
          baseCurrency,
        ),
        action: Text(
          l10n.dashboardCurrencyMismatchAction,
          style: context.labelStyle.copyWith(color: semantic.onDangerContainer),
        ),
      ),
    );
  }

  void _showDetails(
    BuildContext context,
    List<CurrencyMismatch> mismatches,
    String baseCurrency,
  ) {
    final l10n = AppLocalizations.of(context);
    showAppSheet<void>(
      context: context,
      title: l10n.dashboardCurrencyMismatchSheetTitle,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in mismatches)
            FTile(
              title: Text('${m.currency} → $baseCurrency'),
              prefix: const Icon(FLucideIcons.arrowLeftRight),
              subtitle: Text(m.id),
              suffix: const Icon(FLucideIcons.chevronRight),
              onPress: () {
                Navigator.of(ctx).pop();
                context.goNamed(AppRouteNames.fxRates);
              },
            ),
        ],
      ),
    );
  }
}
