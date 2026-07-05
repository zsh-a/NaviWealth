import 'package:decimal/decimal.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import 'physical_asset_meta.dart';

export '../domain/physical_asset_valuation.dart';

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

  /// Baseline valuation. Current valuations are read from `prices`.
  Decimal get currentValuation => meta.purchasePrice;

  DateTime? get lastValuationAt => null;

  DateTime get purchaseDate => meta.purchaseDate;
  Decimal get purchasePrice => meta.purchasePrice;
  String? get address => meta.address;
  String? get linkedLiabilityId => meta.linkedLiabilityId;
  bool get autoDepreciation => meta.autoDepreciation;
  Decimal? get annualResidualRate => meta.annualResidualRate;
}
