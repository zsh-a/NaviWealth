import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/dashboard_providers.dart';
import '../domain/dashboard_models.dart';

/// Warning banner shown above the dashboard when one or more holdings were
/// excluded from the totals because no FX rate is available to convert
/// them into the active base currency.
///
/// Silently dropping foreign-currency rows is what shipped before;
/// the banner makes the omission visible so users don't read a stale total
/// as ground truth. Tapping it surfaces the offending holdings (currency
/// + id) so the user can either record the missing rate or fix the
/// holding's currency.
class CurrencyMismatchBanner extends ConsumerWidget {
  const CurrencyMismatchBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final semantic = SemanticColors.of(context);
    final mismatches = ref.watch(dashboardCurrencyMismatchesProvider);
    if (mismatches.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final base = ref.watch(dashboardBaseCurrencyProvider);
    return ColoredBox(
      color: semantic.dangerContainer,
      child: GestureDetector(
        onTap: () => _showDetails(context, mismatches, base),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            children: [
              Icon(
                FLucideIcons.triangleAlert,
                color: semantic.onDangerContainer,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  l10n.dashboardCurrencyMismatchBanner(mismatches.length, base),
                  style: context.theme.typography.sm.copyWith(
                    color: semantic.onDangerContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                l10n.dashboardCurrencyMismatchAction,
                style: context.theme.typography.sm.copyWith(
                  color: semantic.onDangerContainer,
                ),
              ),
            ],
          ),
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
