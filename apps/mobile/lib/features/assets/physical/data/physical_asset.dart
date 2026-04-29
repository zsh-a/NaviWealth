import 'package:decimal/decimal.dart';

import '../../../../data/db/app_database.dart';
import '../../../../data/domain/enums.dart';
import 'physical_asset_meta.dart';

/// View model joining an [AssetRow] with its parsed [PhysicalAssetMeta].
///
/// Only `AssetType.realEstate` and `AssetType.vehicle` rows are wrapped here;
/// callers filter at the repository boundary so the rest of the app never
/// has to type-check.
class PhysicalAsset {
  PhysicalAsset({required this.row, required this.meta});

  final AssetRow row;
  final PhysicalAssetMeta meta;

  String get id => row.id;
  String get name => row.name ?? row.symbol;
  String get currency => row.currency;
  AssetType get type => row.type;
  bool get isRealEstate => row.type == AssetType.realEstate;
  bool get isVehicle => row.type == AssetType.vehicle;

  /// Last *manually-recorded* valuation (or the purchase price on day 1).
  /// Stored on `Assets.lastPrice` so it round-trips through sync without a
  /// metadata-shape migration.
  Decimal get currentValuation => row.lastPrice ?? meta.purchasePrice;

  DateTime? get lastValuationAt => row.lastPriceAt;

  DateTime get purchaseDate => meta.purchaseDate;
  Decimal get purchasePrice => meta.purchasePrice;
  String? get address => meta.address;
  String? get linkedLiabilityId => meta.linkedLiabilityId;
  bool get autoDepreciation => meta.autoDepreciation;
  Decimal? get annualResidualRate => meta.annualResidualRate;
}

/// One point on the valuation history chart. Sourced from
/// `Transactions` rows with `type = valuationAdjust`, plus a synthesised
/// "purchase" point so the chart starts at the cost basis.
class ValuationPoint {
  const ValuationPoint({
    required this.asOf,
    required this.value,
    required this.kind,
    this.note,
  });

  final DateTime asOf;
  final Decimal value;
  final ValuationPointKind kind;
  final String? note;
}

enum ValuationPointKind {
  /// Synthesised from `PhysicalAssetMeta.purchasePrice`. Always the first
  /// point on the chart.
  purchase,

  /// User-entered manual update. Backed by a `valuationAdjust` transaction.
  manual,

  /// Computed point from the depreciation curve (vehicles with
  /// `autoDepreciation = true`). Not persisted — only shown on the chart.
  projected,
}
