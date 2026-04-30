import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/dashboard_providers.dart';
import '../domain/dashboard_models.dart';

/// Warning banner shown above the dashboard when one or more holdings were
/// excluded from the totals because no FX rate is available to convert
/// them into the active base currency.
///
/// FIR-73: silently dropping foreign-currency rows is what shipped before;
/// the banner makes the omission visible so users don't read a stale total
/// as ground truth. Tapping it surfaces the offending holdings (currency
/// + id) so the user can either record the missing rate or fix the
/// holding's currency.
class CurrencyMismatchBanner extends ConsumerWidget {
  const CurrencyMismatchBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mismatches = ref.watch(dashboardCurrencyMismatchesProvider);
    if (mismatches.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final base = ref.watch(dashboardBaseCurrencyProvider);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: InkWell(
        onTap: () => _showDetails(context, mismatches, base),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.s16,
            vertical: Spacing.s8,
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: Spacing.s8),
              Expanded(
                child: Text(
                  l10n.dashboardCurrencyMismatchBanner(
                    mismatches.length,
                    base,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.s8),
              Text(
                l10n.dashboardCurrencyMismatchAction,
                style: theme.textTheme.labelLarge?.copyWith(
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.s16,
            Spacing.s8,
            Spacing.s16,
            Spacing.s16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.dashboardCurrencyMismatchSheetTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.s8),
              for (final m in mismatches)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.currency_exchange),
                  title: Text('${m.currency} → $baseCurrency'),
                  subtitle: Text(m.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
