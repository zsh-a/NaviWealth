import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/features/finance/data/domain/asset.dart';

import '../../../app/master_detail_layout.dart';
import '../../../app/route_paths.dart';
import '../../../app/selection_query.dart';
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
    final l10n = AppLocalizations.of(context);
    final qty = snapshot?.quantity;
    final displayValue = snapshot?.marketValueInAssetCurrency;
    final hasQty = qty != null && qty.sign != 0;
    final qtyLabel = hasQty
        ? l10n.securitiesHoldingQuantity('$qty')
        : l10n.securitiesHoldingFlat;
    final title = _securityTitle(asset);

    return MergeSemantics(
      child: GestureDetector(
        onTap: () => _onTap(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: selected
              ? context.theme.colors.primary.withValues(
                  alpha: AppOpacity.subtle,
                )
              : null,
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s16,
              vertical: AppSpacing.s12,
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
                          title,
                          style: context.theme.typography.md,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        qtyLabel,
                        style: context.theme.typography.xs.copyWith(
                          color: context.theme.colors.mutedForeground,
                          fontFeatures: hasQty
                              ? TypographyTokens.tabularFigures
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
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
    );
  }

  void _onTap(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (MasterDetailLayout.shouldUseMasterDetail(width)) {
      replaceSelectedQuery(context, path: AppRoutes.wealth, selected: asset.id);
    } else {
      context.go(AppRoutes.wealthAsset(asset.id));
    }
  }

  String _securityTitle(Asset asset) {
    final name = asset.name?.trim();
    if (name == null || name.isEmpty) return asset.symbol;
    if (name.toUpperCase() == asset.symbol.trim().toUpperCase()) {
      return asset.symbol;
    }
    return '${asset.symbol} · $name';
  }
}
