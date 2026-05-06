import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../assets/assets_page.dart';

/// Portfolio tab — shows the unified asset list (securities, manual assets,
/// physical assets) with a simplified add button in the app bar.
class PortfolioPage extends ConsumerWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.navPortfolio),
      ),
      body: const AssetsPage(),
    );
  }
}
