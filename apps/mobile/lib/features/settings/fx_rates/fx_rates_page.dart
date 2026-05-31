import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import '../../../design_system/design_system.dart';
import '../../../domain/entities/fx_rate.dart' as dom;
import '../../../l10n/gen/app_localizations.dart';
import '../../settings/data/base_currency_preference.dart';
import 'providers.dart';

/// FX-rate management page.
///
/// Rates are auto-synced from Yahoo Finance on app launch. Users can
/// trigger a manual refresh via the app bar button. Swipe-to-delete is
/// kept for cleanup of stale or incorrect entries.
class FxRatesPage extends ConsumerWidget {
  const FxRatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ratesAsync = ref.watch(fxRatesStreamProvider);

    return FScaffold(
      header: FHeader.nested(
        title: Text(l10n.fxRatesAppBarTitle),
        prefixes: [backHeaderAction(context)],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.refreshCw),
            onPress: () => _refresh(context, ref),
          ),
        ],
      ),
      childPad: false,
      child: ratesAsync.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rates) => _RateList(rates: rates),
      ),
    );
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    // Show a brief toast while syncing.
    AppMessenger.show(context, ToastKind.info, l10n.fxRatesRefreshing);

    try {
      final service = await ref.read(fxRateSyncServiceProvider.future);
      final base = ref.read(baseCurrencyProvider);
      final accounts = await ref.read(accountsStreamProvider.future);
      final currencies = accounts.map((a) => a.currency).toSet();
      await service.syncRates(
        baseCurrency: base,
        accountCurrencies: currencies,
      );
    } catch (_) {
      // Errors are logged; the user sees whatever rates are already stored.
    }
  }
}

class _RateList extends ConsumerWidget {
  const _RateList({required this.rates});

  final List<dom.FxRate> rates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (rates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Center(
          child: Text(
            l10n.fxRatesEmpty,
            textAlign: TextAlign.center,
            style: context.theme.typography.sm.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ),
      );
    }
    final dateFmt = DateFormat.yMMMd();
    // Most-recent first.
    final ordered = [...rates]..sort((a, b) => b.date.compareTo(a.date));
    final semantic = SemanticColors.of(context);
    final colors = context.theme.colors;
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.s16),
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s6),
      itemBuilder: (ctx, i) {
        final r = ordered[i];
        return Dismissible(
          key: ValueKey('${r.base}-${r.quote}-${r.date.toIso8601String()}'),
          direction: DismissDirection.endToStart,
          background: Container(
            decoration: BoxDecoration(
              color: semantic.dangerContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
            child: Icon(FLucideIcons.trash2, color: semantic.danger),
          ),
          confirmDismiss: (_) async {
            final repo = await ref.read(fxRateRepositoryProvider.future);
            await repo.deleteByNaturalKey(
              base: r.base,
              quote: r.quote,
              date: r.date,
            );
            return true;
          },
          child: SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14, vertical: AppSpacing.s12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.foreground.withValues(alpha: AppOpacity.whisper),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    FLucideIcons.arrowLeftRight,
                    size: AppIconSizes.h18,
                    color: colors.mutedForeground,
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '1 ${r.base} = ${r.rate} ${r.quote}',
                        style: context.theme.typography.sm.copyWith(
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        '${dateFmt.format(r.date)} · ${r.source}',
                        style: context.theme.typography.xs.copyWith(
                          color: colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
