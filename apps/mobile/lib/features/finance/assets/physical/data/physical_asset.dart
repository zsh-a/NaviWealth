import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import '../domain/physical_asset_valuation.dart';
import 'physical_asset_meta.dart';

export '../domain/physical_asset_valuation.dart';

/// View model joining an [AssetRow] with its parsed [PhysicalAssetMeta].
///
/// Only `AssetType.realEstate` and `AssetType.vehicle` rows are wrapped here;
/// callers filter at the repository boundary so the rest of the app never
/// has to type-check.
class PhysicalAsset {
  PhysicalAsset({
    required this.row,
    required this.meta,
    Iterable<ValuationPoint> valuationHistory = const [],
  }) : valuationHistory = List.unmodifiable(valuationHistory);

  final AssetRow row;
  final PhysicalAssetMeta meta;

  /// Persisted valuation observations, in chronological order. The purchase
  /// point is included by the repository so consumers can render and replay
  /// the series without a second query.
  final List<ValuationPoint> valuationHistory;

  String get id => row.id;
  String get name => row.name ?? row.symbol;
  String get currency => row.currency;
  AssetType get type => row.type;
  bool get isRealEstate => row.type == AssetType.realEstate;
  bool get isVehicle => row.type == AssetType.vehicle;

  /// Latest persisted valuation. The asset row only carries the purchase
  /// baseline; all later values are read from `prices`.
  Decimal get currentValuation {
    ValuationPoint? latest;
    for (final point in valuationHistory) {
      if (point.kind == ValuationPointKind.manual) latest = point;
    }
    return latest?.value ?? meta.purchasePrice;
  }

  /// Date of the latest valuation after purchase. The initial purchase point
  /// is not surfaced as a separate "last valuation" date.
  DateTime? get lastValuationAt {
    ValuationPoint? latest;
    for (final point in valuationHistory) {
      if (point.kind == ValuationPointKind.manual) latest = point;
    }
    final point = latest;
    if (point == null || !point.asOf.isAfter(meta.purchaseDate)) return null;
    return point.asOf;
  }

  DateTime get purchaseDate => meta.purchaseDate;
  Decimal get purchasePrice => meta.purchasePrice;
  String? get address => meta.address;
  String? get linkedLiabilityId => meta.linkedLiabilityId;
  bool get autoDepreciation => meta.autoDepreciation;
  Decimal? get annualResidualRate => meta.annualResidualRate;
}
