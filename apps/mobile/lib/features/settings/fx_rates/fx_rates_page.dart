import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/providers.dart';
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
        suffixes: [
          FHeaderAction(
            icon: const Icon(Icons.sync),
            onPress: () => _refresh(context, ref),
          ),
        ],
      ),
      childPad: false,
      child: Material(
        color: Colors.transparent,
        child: ratesAsync.when(
          loading: () => const Center(child: FCircularProgress()),
          error: (e, _) => Center(child: Text('$e')),
          data: (rates) => _RateList(rates: rates),
        ),
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
        padding: Spacing.pageMobile,
        child: Center(
          child: Text(
            l10n.fxRatesEmpty,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.theme.colors.mutedForeground,
            ),
          ),
        ),
      );
    }
    final dateFmt = DateFormat.yMMMd();
    // Most-recent first.
    final ordered = [...rates]..sort((a, b) => b.date.compareTo(a.date));
    return ListView.separated(
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const FDivider(),
      itemBuilder: (ctx, i) {
        final r = ordered[i];
        return Dismissible(
          key: ValueKey('${r.base}-${r.quote}-${r.date.toIso8601String()}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Theme.of(ctx).colorScheme.errorContainer,
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Icon(
              Icons.delete_outline,
              color: Theme.of(ctx).colorScheme.onErrorContainer,
            ),
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
          child: FTile(
            title: Text('1 ${r.base} = ${r.rate} ${r.quote}'),
            prefix: const Icon(Icons.currency_exchange),
            subtitle: Text('${dateFmt.format(r.date)} · ${r.source}'),
          ),
        );
      },
    );
  }
}
