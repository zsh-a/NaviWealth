import 'package:decimal/decimal.dart';

import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/liability.dart';
import '../../../data/domain/manual_asset_metadata.dart';
import '../../../data/repositories/manual_asset_repository.dart';
import '../../../domain/services/currency_converter.dart';
import '../../../domain/values/money.dart';
import '../../assets/physical/data/physical_asset.dart';
import '../../liabilities/domain/liability_summary.dart';
import 'dashboard_models.dart';

/// Pure aggregator that turns the live asset / liability streams into a
/// [DashboardSnapshot]. Intentionally framework-agnostic so it can be unit
/// tested without a Flutter binding.
///
/// The function tolerates partial data: any asset whose value cannot be
/// converted to [baseCurrency] (missing FX rate) is dropped from the
/// snapshot but reported via [onCurrencyMismatch] so the UI can surface a
/// "data incomplete" banner. The dropped asset's id is passed in so the
/// banner can deep-link to the offending row.
class DashboardAggregator {
  DashboardAggregator({
    required this.converter,
    required this.baseCurrency,
    required this.asOf,
    this.onCurrencyMismatch,
  });

  final CurrencyConverter converter;
  final String baseCurrency;
  final DateTime asOf;

  /// Optional callback invoked when an asset / liability is silently
  /// dropped because its currency cannot be converted to [baseCurrency].
  /// Production callers wire this to a logger or a UI banner; tests can
  /// observe it directly to assert behaviour.
  final void Function(String id, String currency)? onCurrencyMismatch;

  DashboardSnapshot aggregate({
    required Iterable<Asset> manualAssets,
    required Iterable<PhysicalAsset> physicalAssets,
    required Iterable<Liability> liabilities,
    required Iterable<LiabilitySummary> liabilitySummaries,
  }) {
    final byCategory = <AssetCategory, List<CategoryItem>>{};

    for (final asset in manualAssets) {
      final item = _itemForManualAsset(asset);
      if (item == null) continue;
      final cat = categoryForAssetType(asset.type);
      byCategory.putIfAbsent(cat, () => []).add(item);
    }

    for (final asset in physicalAssets) {
      final item = _itemForPhysicalAsset(asset);
      if (item == null) continue;
      final cat = categoryForAssetType(asset.type);
      byCategory.putIfAbsent(cat, () => []).add(item);
    }

    final summaryById = {
      for (final s in liabilitySummaries) s.liability.id: s,
    };
    final liabilityItems = <CategoryItem>[];
    for (final liability in liabilities) {
      final summary = summaryById[liability.id];
      final outstanding =
          summary?.remainingPrincipal ?? liability.principal;
      if (outstanding.sign <= 0) continue;
      final converted = _tryConvert(
        liability.id,
        Money(outstanding, liability.currency),
      );
      if (converted == null) continue;
      liabilityItems.add(
        CategoryItem(
          id: liability.id,
          name: liability.name,
          subtitle: _liabilityTypeLabel(liability.type),
          valueInBase: converted,
          nativeAmount: outstanding,
          nativeCurrency: liability.currency,
          routeHint: '/assets/liabilities/${liability.id}',
        ),
      );
    }
    if (liabilityItems.isNotEmpty) {
      byCategory[AssetCategory.liability] = liabilityItems;
    }

    final allocations = <CategoryAllocation>[];
    for (final category in AssetCategory.values) {
      final items = byCategory[category];
      if (items == null || items.isEmpty) continue;
      items.sort((a, b) => b.valueInBase.amount.compareTo(a.valueInBase.amount));
      final total = items.fold<Money>(
        Money.zero(baseCurrency),
        (acc, item) => acc + item.valueInBase,
      );
      allocations.add(
        CategoryAllocation(
          category: category,
          totalInBase: total,
          items: List.unmodifiable(items),
        ),
      );
    }

    var totalAssets = Money.zero(baseCurrency);
    var totalLiabilities = Money.zero(baseCurrency);
    for (final alloc in allocations) {
      if (alloc.isLiability) {
        totalLiabilities = totalLiabilities + alloc.totalInBase;
      } else {
        totalAssets = totalAssets + alloc.totalInBase;
      }
    }

    return DashboardSnapshot(
      asOf: asOf,
      baseCurrency: baseCurrency,
      allocations: List.unmodifiable(allocations),
      totalAssets: totalAssets,
      totalLiabilities: totalLiabilities,
      netWorth: totalAssets - totalLiabilities,
    );
  }

  CategoryItem? _itemForManualAsset(Asset asset) {
    final price = asset.lastPrice ?? Decimal.zero;
    if (price.sign <= 0) return null;
    final converted = _tryConvert(asset.id, Money(price, asset.currency));
    if (converted == null) return null;
    return CategoryItem(
      id: asset.id,
      name: asset.name ?? asset.symbol,
      subtitle: _manualAssetSubtitle(asset),
      valueInBase: converted,
      nativeAmount: price,
      nativeCurrency: asset.currency,
      routeHint: '/assets/${asset.id}',
    );
  }

  CategoryItem? _itemForPhysicalAsset(PhysicalAsset asset) {
    final value = asset.currentValuation;
    if (value.sign <= 0) return null;
    final converted = _tryConvert(
      asset.id,
      Money(value, asset.currency),
    );
    if (converted == null) return null;
    return CategoryItem(
      id: asset.id,
      name: asset.name,
      subtitle: asset.address,
      valueInBase: converted,
      nativeAmount: value,
      nativeCurrency: asset.currency,
      routeHint: '/assets/physical/${asset.id}',
    );
  }

  Money? _tryConvert(String id, Money amount) {
    if (amount.currency == baseCurrency) return amount;
    try {
      return converter.convert(amount, baseCurrency, on: asOf);
    } on FxRateNotFoundError {
      onCurrencyMismatch?.call(id, amount.currency);
      return null;
    }
  }

  String? _manualAssetSubtitle(Asset asset) {
    final meta = asset.manualMetadata;
    if (meta is DepositMetadata) {
      final pct = (meta.interestRate * Decimal.fromInt(100)).toString();
      return '$pct% · ${asset.currency}';
    }
    if (meta is WealthProductMetadata) {
      final pct =
          (meta.expectedAnnualReturn * Decimal.fromInt(100)).toString();
      return '$pct% · ${asset.currency}';
    }
    return asset.currency;
  }

  String _liabilityTypeLabel(LiabilityType type) {
    switch (type) {
      case LiabilityType.mortgage:
        return '房贷';
      case LiabilityType.carLoan:
        return '车贷';
      case LiabilityType.creditCard:
        return '信用卡';
      case LiabilityType.consumerLoan:
        return '消费贷';
      case LiabilityType.studentLoan:
        return '学生贷款';
      case LiabilityType.marginLoan:
        return '保证金贷款';
      case LiabilityType.other:
        return '其他';
    }
  }
}

