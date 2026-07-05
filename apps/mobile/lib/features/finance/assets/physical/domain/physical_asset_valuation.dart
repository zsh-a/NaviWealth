import 'package:decimal/decimal.dart';

/// One point on the valuation history chart. Sourced from
/// `prices` rows, plus a synthesised "purchase" point so the chart starts
/// at the cost basis.
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

  /// User-entered manual update. Backed by a `prices` observation.
  manual,

  /// Computed point from the depreciation curve (vehicles with
  /// `autoDepreciation = true`). Not persisted; only shown on the chart.
  projected,
}
