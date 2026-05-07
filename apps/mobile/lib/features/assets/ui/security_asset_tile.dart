import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/master_detail_layout.dart';
import '../../../app/route_paths.dart';
import '../../../app/selection_query.dart';
import '../../../data/domain/asset.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../investment/domain/models/holding_snapshot.dart';

class SecurityAssetTile extends StatelessWidget {
  const SecurityAssetTile({
    super.key,
    required this.asset,
    required this.snapshot,
    required this.selected,
    required this.heroEnabled,
  });

  final Asset asset;
  final HoldingSnapshot? snapshot;
  final bool selected;
  final bool heroEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final qty = snapshot?.quantity;
    final displayValue = snapshot?.marketValueInAssetCurrency;
    final hasQty = qty != null && qty.sign != 0;
    final qtyLabel = hasQty
        ? l10n.securitiesHoldingQuantity('$qty')
        : l10n.securitiesHoldingFlat;

    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _onTap(context),
          child: Container(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.10)
                : null,
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.s16,
                vertical: Spacing.s12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OptionalHero(
                          tag: 'asset-${asset.id}-name',
                          enabled: heroEnabled,
                          child: Text(
                            asset.name == null || asset.name!.isEmpty
                                ? asset.symbol
                                : '${asset.symbol} \u00B7 ${asset.name}',
                            style: theme.textTheme.bodyLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: Spacing.s4),
                        Text(
                          qtyLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontFeatures: hasQty
                                ? TypographyTokens.tabularFigures
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Spacing.s12),
                  if (displayValue != null)
                    OptionalHero(
                      tag: 'asset-${asset.id}-value',
                      enabled: heroEnabled,
                      child: MoneyText(
                        amount: displayValue.toDouble(),
                        currencyCode: asset.currency,
                        style: TypographyTokens.numericBody,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (MasterDetailLayout.shouldUseMasterDetail(width)) {
      replaceSelectedQuery(
        context,
        path: AppRoutes.portfolio,
        selected: asset.id,
      );
    } else {
      context.go(AppRoutes.portfolioAsset(asset.id));
    }
  }
}
