import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/theme/design_tokens.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeAppBarTitle)),
      body: ListView(
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        children: [
          const _NetWorthCard(),
          const SizedBox(height: DesignTokens.spaceM),
          _PlaceholderCard(
            title: l10n.homeTodayReturnTitle,
            subtitle: l10n.homeTodayReturnSubtitle,
            icon: Icons.trending_up,
          ),
          const SizedBox(height: DesignTokens.spaceM),
          _PlaceholderCard(
            title: l10n.homeAllocationTitle,
            subtitle: l10n.homeAllocationSubtitle,
            icon: Icons.donut_large,
          ),
          const SizedBox(height: DesignTokens.spaceM),
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
        padding: const EdgeInsets.all(DesignTokens.spaceXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.homeNetWorthTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: DesignTokens.spaceS),
            Text(
              '¥ —',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: DesignTokens.spaceXs),
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
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: DesignTokens.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: DesignTokens.spaceXs),
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
