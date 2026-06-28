import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/data/domain/account.dart';

import '../../../design_system/design_system.dart';

class AssetSectionHeader extends StatelessWidget {
  const AssetSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8, bottom: AppSpacing.s8),
      child: Text(title, style: context.theme.typography.body.md),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s8,
      ),
      color: context.theme.colors.secondary.withValues(alpha: AppOpacity.muted),
      child: Text(
        subtitle != null && subtitle.isNotEmpty
            ? '${account!.name} \u00B7 $subtitle'
            : account?.name ?? accountId,
        style: context.captionMediumStyle,
      ),
    );
  }
}

class TertiaryRowSurface extends StatelessWidget {
  const TertiaryRowSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SoftCard(child: child);
  }
}
