import 'package:flutter/material.dart';

import '../../../data/domain/asset.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

class AssetSummaryCard extends StatelessWidget {
  const AssetSummaryCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return LiquidGlassCard(
      padding: Spacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(asset.symbol, style: theme.textTheme.titleMedium),
          if (asset.name != null) ...[
            const SizedBox(height: Spacing.s4),
            Text(asset.name!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: Spacing.s8),
          Text(
            '${asset.market ?? l10n.assetDetailUnknown} \u00B7 ${asset.currency}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
