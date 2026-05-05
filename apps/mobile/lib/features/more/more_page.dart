import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design_system/design_system.dart';
import '../../l10n/gen/app_localizations.dart';
import '../ai_chat/ui/ai_chat_sheet.dart';

/// More tab — hub page with navigation cards for secondary features:
/// Accounts, Analytics, FIRE, AI Assistant, Rebalance, Settings.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final items = <_MoreItem>[
      _MoreItem(
        icon: Icons.account_balance_outlined,
        title: l10n.navAccounts,
        subtitle: l10n.moreAccountsSubtitle,
        onTap: () => context.push('/accounts'),
      ),
      _MoreItem(
        icon: Icons.pie_chart_outline,
        title: l10n.navAnalytics,
        subtitle: l10n.moreAnalyticsSubtitle,
        onTap: () => context.push('/analytics'),
      ),
      _MoreItem(
        icon: Icons.flag_outlined,
        title: l10n.navFire,
        subtitle: l10n.moreFireSubtitle,
        onTap: () => context.push('/fire'),
      ),
      _MoreItem(
        icon: Icons.auto_awesome_outlined,
        title: l10n.homeAiAssistantTooltip,
        subtitle: l10n.moreAiSubtitle,
        onTap: () => showAiChatSheet(context),
      ),
      _MoreItem(
        icon: Icons.balance_outlined,
        title: 'Rebalance',
        subtitle: l10n.moreRebalanceSubtitle,
        onTap: () => context.push('/rebalance'),
      ),
      _MoreItem(
        icon: Icons.settings_outlined,
        title: l10n.navSettings,
        subtitle: l10n.moreSettingsSubtitle,
        onTap: () => context.push('/settings'),
      ),
    ];

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(l10n.navMore),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: l10n.homeAiAssistantTooltip,
            onPressed: () => showAiChatSheet(context),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
          return GridView.builder(
            padding: Spacing.pageMobile,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: Spacing.s12,
              crossAxisSpacing: Spacing.s12,
              childAspectRatio: 1.2,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _MoreCard(item: items[i]),
          );
        },
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem({
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

class _MoreCard extends StatelessWidget {
  const _MoreCard({required this.item});

  final _MoreItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LiquidGlassCard(
      padding: Spacing.card,
      onTap: item.onTap,
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
    );
  }
}
