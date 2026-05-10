import '../../../app/route_paths.dart';
import '../../../data/domain/asset.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/liability.dart';
import '../../../domain/entities/fx_rate.dart';
import '../../../domain/services/currency_converter.dart';
import '../../../domain/values/money.dart';
import '../../assets/physical/data/physical_asset.dart';
import '../../investment/domain/models/holding_snapshot.dart';
import '../../liabilities/domain/liability_summary.dart';
import 'dashboard_models.dart';

/// Top-level entry point for running the aggregation in a background isolate
/// via [Isolate.run]. All parameters are plain Dart objects — safe to send
/// across isolate boundaries. The [fxRates] list is used to reconstruct a
/// [CurrencyConverter] inside the isolate.
DashboardSnapshot aggregateDashboard({
  required String baseCurrency,
  required DateTime asOf,
  required List<FxRate> fxRates,
  required Iterable<ManualAssetValuation> manualAssets,
  required Iterable<PhysicalAsset> physicalAssets,
  required Iterable<Liability> liabilities,
  required Iterable<LiabilitySummary> liabilitySummaries,
  Iterable<SecurityHolding> securitiesHoldings = const [],
}) {
  final converter = FxRateCurrencyConverter(InMemoryFxRateLookup(fxRates));
  final aggregator = DashboardAggregator(
    converter: converter,
    baseCurrency: baseCurrency,
    asOf: asOf,
  );
  return aggregator.aggregate(
    manualAssets: manualAssets,
    physicalAssets: physicalAssets,
    liabilities: liabilities,
    liabilitySummaries: liabilitySummaries,
    securitiesHoldings: securitiesHoldings,
  );
}

/// One row of the holdings pipeline as the dashboard sees it: the asset
/// metadata for category / labelling, paired with the priced snapshot.
typedef SecurityHolding = ({Asset asset, HoldingSnapshot snapshot});

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
    required Iterable<ManualAssetValuation> manualAssets,
    required Iterable<PhysicalAsset> physicalAssets,
    required Iterable<Liability> liabilities,
    required Iterable<LiabilitySummary> liabilitySummaries,
    Iterable<SecurityHolding> securitiesHoldings = const [],
  }) {
    final byCategory = <AssetCategory, List<CategoryItem>>{};
    _mismatches.clear();

    for (final asset in manualAssets) {
      final item = _itemForManualAsset(asset);
      if (item == null) continue;
      final cat = categoryForAssetType(asset.asset.type);
      byCategory.putIfAbsent(cat, () => []).add(item);
    }

    for (final asset in physicalAssets) {
      final item = _itemForPhysicalAsset(asset);
      if (item == null) continue;
      final cat = categoryForAssetType(asset.type);
      byCategory.putIfAbsent(cat, () => []).add(item);
    }

    for (final holding in securitiesHoldings) {
      final item = _itemForSecurityHolding(holding);
      if (item == null) continue;
      final cat = categoryForAssetType(holding.asset.type);
      byCategory.putIfAbsent(cat, () => []).add(item);
    }

    final summaryById = {for (final s in liabilitySummaries) s.liability.id: s};
    final liabilityItems = <CategoryItem>[];
    for (final liability in liabilities) {
      final summary = summaryById[liability.id];
      final outstanding = summary?.remainingPrincipal ?? liability.principal;
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
          subtitle: null,
          liabilityType: liability.type,
          valueInBase: converted,
          nativeAmount: outstanding,
          nativeCurrency: liability.currency,
          routeHint: AppRoutes.liability(liability.id),
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
      items.sort(
        (a, b) => b.valueInBase.amount.compareTo(a.valueInBase.amount),
      );
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
      currencyMismatches: List.unmodifiable(_mismatches),
    );
  }

  final List<CurrencyMismatch> _mismatches = [];

  CategoryItem? _itemForManualAsset(ManualAssetValuation valued) {
    final value = valued.valueAt(asOf);
    if (value == null) return null;
    // Cash can go negative (e.g. trade overdraws); include it so net worth
    // stays accurate. Other manual assets (deposits, wealth products) with
    // non-positive values are still excluded.
    if (value.sign <= 0 && valued.asset.type != AssetType.cash) return null;
    final asset = valued.asset;
    final converted = _tryConvert(asset.id, Money(value, asset.currency));
    if (converted == null) return null;
    return CategoryItem(
      id: asset.id,
      name: asset.name ?? asset.symbol,
      subtitle: asset.type == AssetType.cash ? null : asset.symbol,
      valueInBase: converted,
      nativeAmount: value,
      nativeCurrency: asset.currency,
      routeHint: AppRoutes.accountAsset(asset.id),
    );
  }

  /// Build a [CategoryItem] for a securities position. The market value is
  /// already in [baseCurrency] (the holding service ran the FX conversion),
  /// so we wrap it directly without re-converting. Positions with zero
  /// quantity or a missing price flow through with a zero `marketValueInBase`
  /// — those are dropped here so a sold-out lot doesn't pollute the totals.
  CategoryItem? _itemForSecurityHolding(SecurityHolding holding) {
    final snap = holding.snapshot;
    if (snap.marketValueInBase.sign <= 0) return null;
    final asset = holding.asset;
    return CategoryItem(
      id: asset.id,
      name: asset.name ?? asset.symbol,
      subtitle: '${snap.quantity} · ${asset.currency}',
      valueInBase: Money(snap.marketValueInBase, baseCurrency),
      nativeAmount: snap.marketValueInAssetCurrency,
      nativeCurrency: snap.assetCurrency,
      routeHint: AppRoutes.accountAsset(asset.id),
    );
  }

  CategoryItem? _itemForPhysicalAsset(PhysicalAsset asset) {
    final value = asset.currentValuation;
    if (value.sign <= 0) return null;
    final converted = _tryConvert(asset.id, Money(value, asset.currency));
    if (converted == null) return null;
    return CategoryItem(
      id: asset.id,
      name: asset.name,
      subtitle: asset.address,
      valueInBase: converted,
      nativeAmount: value,
      nativeCurrency: asset.currency,
      routeHint: AppRoutes.physicalAsset(asset.id),
    );
  }

  Money? _tryConvert(String id, Money amount) {
    if (amount.currency == baseCurrency) return amount;
    try {
      return converter.convert(amount, baseCurrency, on: asOf);
    } on FxRateNotFoundError {
      _mismatches.add(CurrencyMismatch(id: id, currency: amount.currency));
      onCurrencyMismatch?.call(id, amount.currency);
      return null;
    }
  }
}
