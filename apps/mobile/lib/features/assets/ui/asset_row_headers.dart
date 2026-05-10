import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../data/domain/account.dart';

class AssetSectionHeader extends StatelessWidget {
  const AssetSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(title, style: context.theme.typography.md),
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
    final subtitle = account?.institution;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: context.theme.colors.secondary.withValues(alpha: 0.3),
      child: Text(
        subtitle != null && subtitle.isNotEmpty
            ? '${account!.name} \u00B7 $subtitle'
            : account?.name ?? accountId,
        style: context.theme.typography.xs.copyWith(
          color: context.theme.colors.mutedForeground,
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
