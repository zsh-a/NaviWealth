import 'dart:convert';

import 'package:decimal/decimal.dart';

/// Physical-asset-specific fields persisted as JSON in `Assets.metadata_json`.
///
/// We don't extend the `Assets` table for these because the columns would be
/// dead weight on every securities row (which is the bulk of the table). The
/// JSON envelope keeps the synced wire shape constant while letting v2 evolve
/// the metadata shape without a schema migration.
///
/// Forward-compat rule: unknown keys are preserved on read so an older client
/// editing a row written by a newer client doesn't drop fields.
class PhysicalAssetMeta {
  PhysicalAssetMeta({
    this.address,
    required this.purchaseDate,
    required this.purchasePrice,
    this.linkedLiabilityId,
    this.annualResidualRate,
    this.autoDepreciation = false,
    Map<String, Object?>? extra,
  }) : extra = extra ?? const <String, Object?>{};

  /// Optional street address (real-estate only). Free-form text, not parsed.
  final String? address;

  /// Date the asset was purchased. Drives the depreciation curve for vehicles
  /// and is shown on detail pages for both kinds.
  final DateTime purchaseDate;

  /// Purchase price in the asset's currency. The `Assets.lastPrice` column
  /// holds the *current* valuation; this field is the historical anchor and
  /// is never recomputed.
  final Decimal purchasePrice;

  /// Optional link to a `Liabilities.id` (typically a mortgage / car loan).
  /// Stored as a soft reference — the detail page resolves it lazily so a
  /// dangling pointer (deleted liability) just hides the row instead of
  /// crashing.
  final String? linkedLiabilityId;

  /// Annual residual-value rate (vehicles only). 0.85 means "the car is
  /// worth 85% of last year's value at the next anniversary." Stored as
  /// Decimal so the depreciation curve is reproducible across devices that
  /// may differ in `double` precision.
  final Decimal? annualResidualRate;

  /// Whether the depreciation curve should automatically project forward
  /// from the last manual valuation. When `false`, the user pins valuations
  /// manually and the chart only shows actual `valuationAdjust` points.
  final bool autoDepreciation;

  /// Future-proofing pocket. Forward-compat: any keys this version does not
  /// recognise are preserved here and re-emitted on write so we don't lose
  /// data on round-trip through an older client.
  final Map<String, Object?> extra;

  static const String _kAddress = 'address';
  static const String _kPurchaseDate = 'purchase_date';
  static const String _kPurchasePrice = 'purchase_price';
  static const String _kLinkedLiabilityId = 'linked_liability_id';
  static const String _kAnnualResidualRate = 'annual_residual_rate';
  static const String _kAutoDepreciation = 'auto_depreciation';

  static const Set<String> _knownKeys = {
    _kAddress,
    _kPurchaseDate,
    _kPurchasePrice,
    _kLinkedLiabilityId,
    _kAnnualResidualRate,
    _kAutoDepreciation,
  };

  Map<String, Object?> toJson() {
    final out = <String, Object?>{
      if (address != null) _kAddress: address,
      _kPurchaseDate: purchaseDate.toUtc().toIso8601String(),
      _kPurchasePrice: purchasePrice.toString(),
      if (linkedLiabilityId != null) _kLinkedLiabilityId: linkedLiabilityId,
      if (annualResidualRate != null)
        _kAnnualResidualRate: annualResidualRate!.toString(),
      _kAutoDepreciation: autoDepreciation,
    };
    out.addAll(extra);
    return out;
  }

  String encode() => jsonEncode(toJson());

  static PhysicalAssetMeta? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    return fromJson(Map<String, Object?>.from(decoded));
  }

  static PhysicalAssetMeta fromJson(Map<String, Object?> json) {
    final purchaseDateRaw = json[_kPurchaseDate];
    final purchasePriceRaw = json[_kPurchasePrice];
    if (purchaseDateRaw is! String || purchasePriceRaw is! String) {
      throw const FormatException(
        'physical asset metadata missing required fields',
      );
    }
    final extra = <String, Object?>{};
    for (final entry in json.entries) {
      if (!_knownKeys.contains(entry.key)) extra[entry.key] = entry.value;
    }
    return PhysicalAssetMeta(
      address: json[_kAddress] as String?,
      purchaseDate: DateTime.parse(purchaseDateRaw),
      purchasePrice: Decimal.parse(purchasePriceRaw),
      linkedLiabilityId: json[_kLinkedLiabilityId] as String?,
      annualResidualRate: switch (json[_kAnnualResidualRate]) {
        final String s => Decimal.parse(s),
        _ => null,
      },
      autoDepreciation: json[_kAutoDepreciation] == true,
      extra: extra.isEmpty ? null : extra,
    );
  }

  PhysicalAssetMeta copyWith({
    Object? address = _sentinel,
    DateTime? purchaseDate,
    Decimal? purchasePrice,
    Object? linkedLiabilityId = _sentinel,
    Object? annualResidualRate = _sentinel,
    bool? autoDepreciation,
    Map<String, Object?>? extra,
  }) {
    return PhysicalAssetMeta(
      address: address == _sentinel ? this.address : address as String?,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      linkedLiabilityId: linkedLiabilityId == _sentinel
          ? this.linkedLiabilityId
          : linkedLiabilityId as String?,
      annualResidualRate: annualResidualRate == _sentinel
          ? this.annualResidualRate
          : annualResidualRate as Decimal?,
      autoDepreciation: autoDepreciation ?? this.autoDepreciation,
      extra: extra ?? this.extra,
    );
  }
}

/// Marker used so `copyWith` can distinguish "not provided" from "explicitly
/// set to null" for nullable fields.
const Object _sentinel = Object();
