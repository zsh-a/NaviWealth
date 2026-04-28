import 'package:flutter/material.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeAppBarTitle)),
      body: ListView(
        padding: Spacing.pageMobile,
        children: [
          const _NetWorthCard(),
          const SizedBox(height: Spacing.s12),
          _PlaceholderCard(
            title: l10n.homeTodayReturnTitle,
            subtitle: l10n.homeTodayReturnSubtitle,
            icon: Icons.trending_up,
          ),
          const SizedBox(height: Spacing.s12),
          _PlaceholderCard(
            title: l10n.homeAllocationTitle,
            subtitle: l10n.homeAllocationSubtitle,
            icon: Icons.donut_large,
          ),
          const SizedBox(height: Spacing.s12),
          _PlaceholderCard(
            title: l10n.homeFireTitle,
            subtitle: l10n.homeFireSubtitle,
            icon: Icons.flag_outlined,
          ),
        ],
      ),
    );
  }
}

class _NetWorthCard extends StatelessWidget {
  const _NetWorthCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: Spacing.cardHero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.homeNetWorthTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.s8),
            // Net worth is unknown until accounts are linked — pass null and
            // let MoneyText render the placeholder with the right symbol.
            const MoneyText(
              amount: null,
              currencyCode: 'CNY',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              l10n.homeNetWorthSubtitle('CNY'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Spacing.card,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: Spacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: Spacing.s4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
