import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../data/domain/account.dart';
import '../../../design_system/design_system.dart';

class AssetSectionHeader extends StatelessWidget {
  const AssetSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.s8, bottom: Spacing.s8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Sub-header for a group of cash assets under one account.
class CashAccountGroupHeader extends StatelessWidget {
  const CashAccountGroupHeader({
    super.key,
    required this.accountId,
    this.account,
  });

  final String accountId;
  final Account? account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = account?.institution;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.s16,
        vertical: Spacing.s8,
      ),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Text(
        subtitle != null && subtitle.isNotEmpty
            ? '${account!.name} \u00B7 $subtitle'
            : account?.name ?? accountId,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class TertiaryRowSurface extends StatelessWidget {
  const TertiaryRowSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FCard.raw(child: child);
  }
}
