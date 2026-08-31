import 'asset_market.dart';
import 'market_corporate_action.dart';

class CorporateActionProviderCapabilities {
  const CorporateActionProviderCapabilities({
    required this.supportedMarkets,
    required this.supportsRecordDate,
    required this.supportsPayDate,
    required this.supportsRevisions,
    required this.availableOnWeb,
  });

  final Set<AssetMarket> supportedMarkets;
  final bool supportsRecordDate;
  final bool supportsPayDate;
  final bool supportsRevisions;
  final bool availableOnWeb;
}

class CorporateActionFetchRequest {
  const CorporateActionFetchRequest({
    required this.symbol,
    required this.market,
    required this.from,
    required this.to,
  });

  final String symbol;
  final AssetMarket market;
  final DateTime from;
  final DateTime to;
}

enum CorporateActionFetchDisposition {
  success,
  authoritativeEmpty,
  partial,
  stale,
  unsupported,
  failure,
}

class CorporateActionFetchResult {
  CorporateActionFetchResult({
    required this.provider,
    required this.disposition,
    required Iterable<MarketCorporateAction> actions,
    required this.fetchedAt,
    this.error,
    this.warning,
  }) : actions = List<MarketCorporateAction>.unmodifiable(actions);

  final String provider;
  final CorporateActionFetchDisposition disposition;
  final List<MarketCorporateAction> actions;
  final DateTime fetchedAt;
  final Object? error;
  final String? warning;

  bool get hasUsableData =>
      disposition == CorporateActionFetchDisposition.success ||
      disposition == CorporateActionFetchDisposition.authoritativeEmpty ||
      disposition == CorporateActionFetchDisposition.partial ||
      disposition == CorporateActionFetchDisposition.stale;
}

abstract interface class CorporateActionProvider {
  String get name;
  CorporateActionProviderCapabilities get capabilities;

  Future<CorporateActionFetchResult> fetch(CorporateActionFetchRequest request);
}
