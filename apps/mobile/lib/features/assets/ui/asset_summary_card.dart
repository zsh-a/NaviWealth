import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'package:naviwealth/features/finance/data/domain/asset.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

class AssetSummaryCard extends StatelessWidget {
  const AssetSummaryCard({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(asset.symbol, style: context.theme.typography.md),
            if (asset.name != null) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(asset.name!, style: context.theme.typography.sm),
            ],
            const SizedBox(height: AppSpacing.s8),
            Text(
              '${asset.market ?? l10n.assetDetailUnknown} \u00B7 ${asset.currency}',
              style: context.theme.typography.xs.copyWith(
                color: context.theme.colors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
