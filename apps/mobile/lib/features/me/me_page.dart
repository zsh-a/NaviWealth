import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';

/// Me tab — hub page for personal / account management:
/// Accounts, Expenses, AI Assistant, Settings.
class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final items = <_MeItem>[
      _MeItem(
        icon: Icons.account_balance_outlined,
        title: l10n.navAccounts,
        subtitle: l10n.moreAccountsSubtitle,
        onTap: () => context.push('/me/accounts'),
      ),
      _MeItem(
        icon: Icons.receipt_long_outlined,
        title: l10n.navExpenses,
        subtitle: l10n.moreExpenseSubtitle,
        onTap: () => context.push('/me/expenses'),
      ),
      _MeItem(
        icon: Icons.auto_awesome_outlined,
        title: l10n.navAI,
        subtitle: l10n.moreAiSubtitle,
        onTap: () => context.push('/me/ai'),
      ),
      _MeItem(
        icon: Icons.settings_outlined,
        title: l10n.navSettings,
        subtitle: l10n.moreSettingsSubtitle,
        onTap: () => context.push('/me/settings'),
      ),
    ];

    return Scaffold(
      appBar: GlassAppBar(title: Text(l10n.navMe)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 600 ? 2 : 2;
          return GridView.builder(
            padding: Spacing.pageMobile.copyWith(
              bottom: Spacing.pageMobile.bottom +
                  Spacing.floatingBarClearance +
                  MediaQuery.paddingOf(context).bottom,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: Spacing.s12,
              crossAxisSpacing: Spacing.s12,
              childAspectRatio: 1.2,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _MeCard(item: items[i]),
          );
        },
      ),
    );
  }
}

class _MeItem {
  const _MeItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _MeCard extends StatelessWidget {
  const _MeCard({required this.item});

  final _MeItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LiquidGlassCard(
      padding: EdgeInsets.zero,
      onTap: item.onTap,
      child: Padding(
        padding: Spacing.card,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item.icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(height: Spacing.s12),
            Text(
              item.title,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Spacing.s4),
            Text(
              item.subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
