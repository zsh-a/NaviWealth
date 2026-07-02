import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/shell/selection_query.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

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
                          style: context.theme.typography.body.md,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        qtyLabel,
                        style: context.captionStyle.copyWith(
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
      replaceSelectedQuery(
        context,
        path: FinanceRoutes.wealth,
        selected: asset.id,
      );
    } else {
      context.go(FinanceRoutes.wealthAsset(asset.id));
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
