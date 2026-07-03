part of 'allocation_detail_panel.dart';

class _AllocationGroup {
  const _AllocationGroup({
    required this.key,
    required this.label,
    required this.value,
    required this.items,
    required this.icon,
    required this.color,
  });

  final String key;
  final String label;
  final double value;
  final List<CategoryItem> items;
  final IconData icon;
  final Color color;
}

List<_AllocationGroup> _groupsFor(
  DashboardSnapshot snapshot,
  _AllocationDimension dimension,
  AppLocalizations l10n,
) {
  final assetAllocations = snapshot.allocations.where((a) => !a.isLiability);
  final paletteSeed = _PaletteSeed();

  if (dimension == _AllocationDimension.assetClass) {
    return [
      for (final allocation in assetAllocations)
        _AllocationGroup(
          key: allocation.category.name,
          label: AssetCategoryVisuals.label(l10n, allocation.category),
          value: allocation.totalInBase.amount.toDouble(),
          items: allocation.items,
          icon: AssetCategoryVisuals.icon(allocation.category),
          color: paletteSeed.next(),
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));
  }

  final byCurrency = <String, List<CategoryItem>>{};
  for (final allocation in assetAllocations) {
    for (final item in allocation.items) {
      byCurrency.putIfAbsent(item.nativeCurrency, () => []).add(item);
    }
  }

  return [
    for (final entry in byCurrency.entries)
      _AllocationGroup(
        key: entry.key,
        label: entry.key,
        value: entry.value.fold<double>(
          0,
          (sum, item) => sum + item.valueInBase.amount.toDouble(),
        ),
        items: entry.value
          ..sort(
            (a, b) => b.valueInBase.amount.compareTo(a.valueInBase.amount),
          ),
        icon: FLucideIcons.arrowLeftRight,
        color: paletteSeed.next(),
      ),
  ]..sort((a, b) => b.value.compareTo(a.value));
}

class _PaletteSeed {
  var _index = 0;

  Color next() {
    const colors = [
      ColorPalette.cyanBrand500,
      ColorPalette.brand400,
      ExpenseCategoryColors.amberLight,
      ColorPalette.red500,
      ExpenseCategoryColors.violet,
      ColorPalette.green500,
      ExpenseCategoryColors.pink,
      ColorPalette.neutral600,
    ];
    final color = colors[_index % colors.length];
    _index += 1;
    return color;
  }
}
