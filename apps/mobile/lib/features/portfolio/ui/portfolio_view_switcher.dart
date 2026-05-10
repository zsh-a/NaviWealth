import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell_preferences.dart';
import '../../../l10n/gen/app_localizations.dart';

class PortfolioViewSwitcher extends ConsumerWidget {
  const PortfolioViewSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(portfolioViewProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SegmentedButton<PortfolioViewMode>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: PortfolioViewMode.assets,
            icon: const Icon(Icons.list_alt_outlined),
            label: Text(l10n.portfolioViewAssets),
          ),
          ButtonSegment(
            value: PortfolioViewMode.account,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: Text(l10n.portfolioViewAccount),
          ),
          ButtonSegment(
            value: PortfolioViewMode.currency,
            icon: const Icon(Icons.currency_exchange_outlined),
            label: Text(l10n.portfolioViewCurrency),
          ),
          ButtonSegment(
            value: PortfolioViewMode.assetClass,
            icon: const Icon(Icons.donut_large_outlined),
            label: Text(l10n.portfolioViewClass),
          ),
        ],
        selected: {current},
        onSelectionChanged: (selection) {
          ref.read(portfolioViewProvider.notifier).set(selection.single);
        },
      ),
    );
  }
}
