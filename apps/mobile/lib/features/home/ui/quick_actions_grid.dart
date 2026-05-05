import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

/// 2x2 grid of quick action cards for the dashboard (mobile only).
class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final actions = <_QuickAction>[
      _QuickAction(
        icon: Icons.receipt_long_outlined,
        label: l10n.superFabExpense,
        route: '/activity/expenses/new',
      ),
      _QuickAction(
        icon: Icons.swap_horiz,
        label: l10n.superFabTrade,
        route: '/activity/trade',
      ),
      _QuickAction(
        icon: Icons.swap_vert,
        label: l10n.superFabTransfer,
        route: '/activity/accounts/transfer',
      ),
      _QuickAction(
        icon: Icons.account_balance_wallet_outlined,
        label: l10n.superFabAsset,
        route: '/portfolio/new/cash',
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Spacing.s8,
        crossAxisSpacing: Spacing.s8,
        childAspectRatio: 2.4,
      ),
      itemCount: actions.length,
      itemBuilder: (context, i) => _QuickActionCard(action: actions[i]),
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LiquidGlassCard(
      layer: GlassLayer.tertiary,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s12,
        vertical: Spacing.s8,
      ),
      onTap: () => context.push(action.route),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: Radii.brSm,
            ),
            alignment: Alignment.center,
            child: Icon(action.icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: Spacing.s8),
          Expanded(
            child: Text(
              action.label,
              style: theme.textTheme.labelLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
