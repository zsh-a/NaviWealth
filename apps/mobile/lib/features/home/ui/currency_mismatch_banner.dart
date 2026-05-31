import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_paths.dart';
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
    final theme = Theme.of(context);
    final mismatches = ref.watch(dashboardCurrencyMismatchesProvider);
    if (mismatches.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final base = ref.watch(dashboardBaseCurrencyProvider);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: InkWell(
        onTap: () => _showDetails(context, mismatches, base),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                FLucideIcons.triangleAlert,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.dashboardCurrencyMismatchBanner(mismatches.length, base),
                  style: context.theme.typography.sm.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.dashboardCurrencyMismatchAction,
                style: context.theme.typography.sm.copyWith(
                  color: theme.colorScheme.onErrorContainer,
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
    showFSheet<void>(
      side: FLayout.btt,
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dashboardCurrencyMismatchSheetTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
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
        ),
      ),
    );
  }
}
