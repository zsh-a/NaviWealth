import 'package:decimal/decimal.dart';

import 'asset_market.dart';

/// Provider-neutral public corporate-action terms.
///
/// This is market reference data, not a user-confirmed FinanceOS business
/// event. Consumers may project it into a timeline, a paper simulation
/// candidate, or a pre-filled confirmation flow, but must not write it
/// directly into the real investment ledger.
class MarketCorporateAction {
  const MarketCorporateAction({
    required this.id,
    required this.source,
    required this.dataset,
    required this.sourceKey,
    required this.revisionHash,
    required this.identityStrength,
    required this.symbol,
    required this.market,
    required this.kind,
    required this.status,
    this.reportDate,
    this.announcementDate,
    this.recordDate,
    this.exDate,
    this.payDate,
    this.currency,
    this.cashPerShare,
    this.bonusRatio,
    this.capitalizationRatio,
    this.totalStockDistributionRatio,
    this.splitNumerator,
    this.splitDenominator,
    this.note,
  });

  /// Deterministic provider-scoped action id.
  final String id;
  final String source;
  final String dataset;
  final String sourceKey;

  /// Hash of the normalized provider payload. A changed hash under the same
  /// [sourceKey] is a provider revision, not a second business event.
  final String revisionHash;
  final MarketCorporateActionIdentityStrength identityStrength;

  final String symbol;
  final AssetMarket market;
  final MarketCorporateActionKind kind;
  final MarketCorporateActionStatus status;

  final DateTime? reportDate;
  final DateTime? announcementDate;
  final DateTime? recordDate;
  final DateTime? exDate;
  final DateTime? payDate;

  final String? currency;

  /// Gross cash amount per one share/unit in [currency].
  final Decimal? cashPerShare;

  /// New shares per one existing share from a bonus-share distribution.
  final Decimal? bonusRatio;

  /// New shares per one existing share from capital-reserve conversion.
  final Decimal? capitalizationRatio;

  /// Provider-reported combined stock-distribution ratio. It is retained
  /// independently because it must not be guessed into either component.
  final Decimal? totalStockDistributionRatio;

  final int? splitNumerator;
  final int? splitDenominator;
  final String? note;

  bool get hasCashDistribution =>
      cashPerShare != null && cashPerShare! > Decimal.zero;

  bool get hasStockDistribution =>
      (bonusRatio != null && bonusRatio! > Decimal.zero) ||
      (capitalizationRatio != null && capitalizationRatio! > Decimal.zero) ||
      (totalStockDistributionRatio != null &&
          totalStockDistributionRatio! > Decimal.zero);

  bool get hasSplit =>
      splitNumerator != null &&
      splitDenominator != null &&
      splitNumerator! > 0 &&
      splitDenominator! > 0;

  /// Best available date for read-only timeline presentation.
  DateTime? get timelineDate =>
      exDate ?? payDate ?? recordDate ?? announcementDate ?? reportDate;
}

enum MarketCorporateActionKind { distribution, split, rights, drip }

enum MarketCorporateActionStatus {
  proposed,
  approved,
  implemented,
  cancelled,
  unknown,
}

enum MarketCorporateActionIdentityStrength { strong, weak }
