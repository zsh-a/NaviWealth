part of 'allocation_card.dart';

/// Bottom sheet (mobile) / dialog body (wide) listing the assets that
/// roll up into a tapped pie slice. Tapping a row deep-links to the
/// asset's detail page.
class CategoryDrillDownSheet extends StatelessWidget {
  const CategoryDrillDownSheet({
    super.key,
    required this.allocation,
    required this.baseCurrency,
    this.showHeader = true,
  });

  final CategoryAllocation allocation;
  final String baseCurrency;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLiability = allocation.isLiability;
    final total = isLiability
        ? -allocation.totalInBase.amount.toDouble()
        : allocation.totalInBase.amount.toDouble();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s16,
          AppSpacing.s8,
          AppSpacing.s16,
          AppSpacing.s24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              Row(
                children: [
                  Icon(
                    AssetCategoryVisuals.icon(allocation.category),
                    color: context.theme.colors.primary,
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: Text(
                      AssetCategoryVisuals.label(l10n, allocation.category),
                      style: context.theme.typography.body.lg,
                    ),
                  ),
                  MoneyText(
                    amount: total,
                    currencyCode: baseCurrency,
                    showSign: total < 0,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            Text(
              l10n.dashboardDrillDownItemCount(allocation.items.length),
              style: context.captionStyle,
            ),
            const SizedBox(height: AppSpacing.s8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allocation.items.length,
                itemBuilder: (ctx, i) {
                  final item = allocation.items[i];
                  final native = item.nativeAmount.toDouble();
                  final base = item.valueInBase.amount.toDouble();
                  final showFx = item.nativeCurrency != baseCurrency;
                  return FTile(
                    title: Text(item.name),
                    prefix: CircleAvatar(
                      backgroundColor: context.theme.colors.secondary,
                      child: Icon(
                        AssetCategoryVisuals.icon(allocation.category),
                        size: AppIconSizes.h18,
                        color: context.theme.colors.mutedForeground,
                      ),
                    ),
                    subtitle: _itemSubtitle(l10n, item) == null
                        ? null
                        : Text(_itemSubtitle(l10n, item)!),
                    suffix: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        MoneyText(
                          amount: isLiability ? -base : base,
                          currencyCode: baseCurrency,
                          compact: true,
                          showSign: isLiability,
                        ),
                        if (showFx)
                          MoneyText(
                            amount: native,
                            currencyCode: item.nativeCurrency,
                            compact: true,
                            symbolStyle: MoneySymbolStyle.isoCode,
                            style: context.captionStyle,
                          ),
                      ],
                    ),
                    onPress: item.routeHint == null
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            context.push(item.routeHint!);
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Picks the localised secondary line for a drill-down row. Liability
  /// rows carry a [LiabilityType]; everything else uses the pre-rendered
  /// [CategoryItem.subtitle] (which the aggregator builds from rate /
  /// currency hints). Returns null when there's nothing meaningful to show.
  String? _itemSubtitle(AppLocalizations l10n, CategoryItem item) {
    if (item.liabilityType != null) {
      return liabilityTypeLabel(l10n, item.liabilityType!);
    }
    return item.subtitle;
  }
}
