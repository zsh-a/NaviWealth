import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../app/shell_preferences.dart';
import '../../l10n/gen/app_localizations.dart';
import '../assets/assets_page.dart';
import 'ui/portfolio_aggregate_views.dart';
import 'ui/portfolio_view_switcher.dart';

/// Portfolio tab — shows the unified asset list (securities, manual assets,
/// physical assets) with a simplified add button in the app bar.
class PortfolioPage extends ConsumerWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(portfolioViewProvider);

    return FScaffold(
      header: FHeader.nested(title: Text(l10n.navPortfolio)),
      childPad: false,
      child: Material(
          color: Colors.transparent,
          child: Column(
        children: [
          const PortfolioViewSwitcher(),
          Expanded(
            child: switch (view) {
              PortfolioViewMode.assets => const AssetsPage(),
              PortfolioViewMode.account => const PortfolioByAccountView(),
              PortfolioViewMode.currency => const PortfolioByCurrencyView(),
              PortfolioViewMode.assetClass => const PortfolioByClassView(),
            },
          ),
        ],
      ),
        ),
    );
  }
}
