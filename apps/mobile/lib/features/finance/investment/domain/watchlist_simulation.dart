import 'package:decimal/decimal.dart';

import '../../../../core/sync/sync_meta.dart';
import '../../market/domain/asset_market.dart';
import '../../market/domain/market_corporate_action.dart';

/// Quantity evidence is independent of allocation completeness. A valid
/// weight-only allocation remains usable while entitlement quantities are unknown.
enum WatchlistSimulationQuantityCoverage { unavailable, partial, complete }

const kWatchlistSimulationBaselineBasisKey = 'baseline';

String watchlistSimulationAllocationBasisKey(String versionId) =>
    'version:$versionId';

enum WatchlistSimulationAllocationReason { creation, reallocation }

enum WatchlistSimulationAllocationStatus { selected, pending, invalid }

class WatchlistSimulationHoldingInput {
  const WatchlistSimulationHoldingInput({
    required this.symbol,
    required this.market,
    this.rawPrice,
    this.priceCurrency,
    this.priceAsOf,
    this.priceSource,
    this.quantityEligible = true,
  });

  final String symbol;
  final AssetMarket market;
  final Decimal? rawPrice;
  final String? priceCurrency;
  final DateTime? priceAsOf;
  final String? priceSource;

  /// False when quote evidence is stale or otherwise unsuitable for creating
  /// a baseline quantity. Price provenance is still persisted for review.
  final bool quantityEligible;
}

class WatchlistSimulation {
  const WatchlistSimulation({
    required this.id,
    required this.collectionId,
    required this.name,
    required this.baseCurrency,
    required this.startingCapital,
    required this.baselineAt,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final String collectionId;
  final String name;
  final String baseCurrency;
  final Decimal startingCapital;
  final DateTime baselineAt;
  final DateTime createdAt;
  final SyncMeta sync;
}

class ResolvedWatchlistSimulationAllocation {
  const ResolvedWatchlistSimulationAllocation({
    required this.status,
    required this.allocationVersionId,
    required this.cashWeight,
    required this.positions,
    this.quantityCoverage = WatchlistSimulationQuantityCoverage.unavailable,
    String? allocationBasisKey,
    Set<String> validAllocationBasisKeys = const <String>{},
  }) : _allocationBasisKey = allocationBasisKey,
       _validAllocationBasisKeys = validAllocationBasisKeys;

  final WatchlistSimulationAllocationStatus status;
  final String? allocationVersionId;
  final Decimal? cashWeight;
  final List<WatchlistSimulationPosition> positions;
  final WatchlistSimulationQuantityCoverage quantityCoverage;
  final String? _allocationBasisKey;
  final Set<String> _validAllocationBasisKeys;

  String? get allocationBasisKey =>
      _allocationBasisKey ??
      (allocationVersionId == null
          ? null
          : watchlistSimulationAllocationBasisKey(allocationVersionId!));

  Set<String> get validAllocationBasisKeys {
    if (_validAllocationBasisKeys.isNotEmpty) return _validAllocationBasisKeys;
    final basisKey = allocationBasisKey;
    return basisKey == null ? const <String>{} : {basisKey};
  }

  bool get isUsable => status == WatchlistSimulationAllocationStatus.selected;
}

class WatchlistSimulationPosition {
  const WatchlistSimulationPosition({
    required this.id,
    required this.simulationId,
    required this.watchlistItemId,
    required this.targetWeight,
    this.quantity,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final String simulationId;
  final String watchlistItemId;
  final Decimal targetWeight;
  final Decimal? quantity;
  final DateTime createdAt;
  final SyncMeta sync;
}

enum WatchlistSimulationPaperActionState {
  referenceOnly,
  entitlementRecorded,
  receivableGross,
  grossCashPendingTax,
  cancelled,
}

class WatchlistSimulationActionTarget {
  const WatchlistSimulationActionTarget({
    required this.watchlistItemId,
    required this.symbol,
    required this.market,
  });

  final String watchlistItemId;
  final String symbol;
  final AssetMarket market;
}

class WatchlistSimulationActionEntry {
  const WatchlistSimulationActionEntry({
    required this.id,
    required this.simulationId,
    required this.watchlistItemId,
    required this.symbol,
    required this.market,
    required this.source,
    required this.dataset,
    required this.sourceKey,
    required this.revisionHash,
    required this.kind,
    required this.status,
    required this.paperState,
    required this.recordDate,
    required this.exDate,
    required this.payDate,
    required this.currency,
    required this.cashPerShare,
    required this.eligibleQuantity,
    required this.grossAmount,
    this.receivableGrossAmount,
    this.paperCashGrossAmount,
    this.stateAt,
    required this.withholdingTaxAmount,
    required this.netAmount,
    required this.baseCurrencyAmount,
    this.allocationBasisKey,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final String simulationId;
  final String watchlistItemId;
  final String symbol;
  final String market;
  final String source;
  final String dataset;
  final String sourceKey;
  final String revisionHash;
  final MarketCorporateActionKind kind;
  final MarketCorporateActionStatus status;
  final WatchlistSimulationPaperActionState paperState;
  final DateTime? recordDate;
  final DateTime? exDate;
  final DateTime? payDate;
  final String currency;
  final Decimal cashPerShare;
  final Decimal? eligibleQuantity;
  final Decimal? grossAmount;
  final Decimal? receivableGrossAmount;
  final Decimal? paperCashGrossAmount;
  final DateTime? stateAt;
  final Decimal? withholdingTaxAmount;
  final Decimal? netAmount;
  final Decimal? baseCurrencyAmount;
  final String? allocationBasisKey;
  final DateTime createdAt;
  final SyncMeta sync;

  bool get hasPaperValue =>
      eligibleQuantity != null ||
      grossAmount != null ||
      receivableGrossAmount != null ||
      paperCashGrossAmount != null ||
      withholdingTaxAmount != null ||
      netAmount != null ||
      baseCurrencyAmount != null;

  bool get isReferenceOnly =>
      paperState == WatchlistSimulationPaperActionState.referenceOnly &&
      !hasPaperValue;
}

class WatchlistSimulationObservation {
  const WatchlistSimulationObservation({
    required this.id,
    required this.simulationId,
    required this.observationDay,
    required this.observedAt,
    required this.projectedValue,
    required this.weightedDailyChange,
    required this.pricedWeight,
    required this.missingQuoteWeight,
    this.allocationBasisKey,
  });

  final String id;
  final String simulationId;
  final String observationDay;
  final DateTime observedAt;
  final Decimal projectedValue;
  final Decimal weightedDailyChange;
  final Decimal pricedWeight;
  final Decimal missingQuoteWeight;
  final String? allocationBasisKey;
}

/// A daily return that can be merged into a simulation's local observation
/// series. Historical backfills use the same shape as live observations so
/// the repository has one projection/rebuild path.
class WatchlistSimulationObservationInput {
  const WatchlistSimulationObservationInput({
    required this.observedAt,
    required this.weightedDailyChange,
    required this.pricedWeight,
    required this.missingQuoteWeight,
  });

  final DateTime observedAt;
  final Decimal weightedDailyChange;
  final Decimal pricedWeight;
  final Decimal missingQuoteWeight;
}

/// Returns whether an observation belongs to the currently selected
/// allocation lineage.
///
/// The creation baseline has its own explicit basis. All market observations
/// identify a version in the selected predecessor lineage.
bool watchlistSimulationObservationIsInAllocationLineage({
  required String? allocationBasisKey,
  required Set<String> validAllocationBasisKeys,
}) =>
    (allocationBasisKey == kWatchlistSimulationBaselineBasisKey) ||
    validAllocationBasisKeys.contains(allocationBasisKey);

enum WatchlistSimulationSaveFailure { syncing, changed }

class WatchlistSimulationSaveException implements Exception {
  const WatchlistSimulationSaveException(this.reason);

  final WatchlistSimulationSaveFailure reason;
}
