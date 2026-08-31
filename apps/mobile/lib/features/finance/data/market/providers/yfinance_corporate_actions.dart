/// Parse provider-neutral corporate actions out of a Yahoo Finance `chart`
/// response.
///
/// Pure function — no I/O or logging. The compatibility
/// [parseYahooCorporateActions] projection remains for the existing investment
/// timeline while new consumers use [parseYahooMarketCorporateActions].
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:naviwealth/features/finance/investment/domain/reporting/event_timeline.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

const _source = 'yfinance';
const _dataset = 'yahoo_chart';

List<MarketCorporateAction> parseYahooMarketCorporateActions({
  required Map<String, Object?> responseBody,
  required String symbol,
  required String currency,
  required AssetMarket market,
}) {
  final result = _firstResult(responseBody);
  if (result == null) return const [];

  final events = result['events'];
  if (events is! Map) return const [];

  final upperSymbol = symbol.toUpperCase();
  final upperCurrency = currency.toUpperCase();
  final out = <MarketCorporateAction>[];

  final dividends = events['dividends'];
  if (dividends is Map) {
    for (final entry in dividends.entries) {
      final event = _parseDividend(
        entry.value,
        upperSymbol,
        upperCurrency,
        market,
      );
      if (event != null) out.add(event);
    }
  }

  final splits = events['splits'];
  if (splits is Map) {
    for (final entry in splits.entries) {
      final event = _parseSplit(entry.value, upperSymbol, market);
      if (event != null) out.add(event);
    }
  }

  return out;
}

/// Compatibility projection for the existing investment event timeline.
List<CorporateActionEvent> parseYahooCorporateActions({
  required Map<String, Object?> responseBody,
  required String symbol,
  required String currency,
}) {
  final market = inferAssetMarket(symbol.toUpperCase());
  final actions = parseYahooMarketCorporateActions(
    responseBody: responseBody,
    symbol: symbol,
    currency: currency,
    market: market,
  );
  return [
    for (final action in actions)
      if (action.kind == MarketCorporateActionKind.distribution &&
          action.hasCashDistribution &&
          action.timelineDate != null)
        CorporateActionEvent(
          id: 'div_${action.symbol}_${_day(action.timelineDate!)}',
          symbol: action.symbol,
          kind: CorporateActionKind.cashDividend,
          scheduledFor: action.timelineDate!,
          cashAmount: action.cashPerShare!,
          currency: action.currency ?? currency.toUpperCase(),
        )
      else if (action.kind == MarketCorporateActionKind.split &&
          action.hasSplit &&
          action.timelineDate != null)
        CorporateActionEvent(
          id: 'split_${action.symbol}_${_day(action.timelineDate!)}',
          symbol: action.symbol,
          kind: CorporateActionKind.split,
          scheduledFor: action.timelineDate!,
          cashAmount: Decimal.zero,
          currency: currency.toUpperCase(),
          ratio: SplitRatio(action.splitNumerator!, action.splitDenominator!),
        ),
  ];
}

Map<String, Object?>? _firstResult(Map<String, Object?> body) {
  final chart = body['chart'];
  if (chart is! Map) return null;
  final results = chart['result'];
  if (results is! List || results.isEmpty) return null;
  final first = results.first;
  if (first is! Map) return null;
  return first.cast<String, Object?>();
}

MarketCorporateAction? _parseDividend(
  Object? raw,
  String symbol,
  String currency,
  AssetMarket market,
) {
  if (raw is! Map) return null;
  final date = _epochSecondsAsUtc(raw['date']);
  final amount = _decimal(raw['amount']);
  if (date == null || amount == null || amount < Decimal.zero) return null;
  final day = _day(date);
  final sourceKey = 'div:$symbol:$day';
  return MarketCorporateAction(
    id: '$_source:$_dataset:$sourceKey',
    source: _source,
    dataset: _dataset,
    sourceKey: sourceKey,
    revisionHash: _hash('$sourceKey|$currency|$amount'),
    identityStrength: MarketCorporateActionIdentityStrength.strong,
    symbol: symbol,
    market: market,
    kind: MarketCorporateActionKind.distribution,
    status: MarketCorporateActionStatus.unknown,
    exDate: date,
    currency: currency,
    cashPerShare: amount,
  );
}

MarketCorporateAction? _parseSplit(
  Object? raw,
  String symbol,
  AssetMarket market,
) {
  if (raw is! Map) return null;
  final date = _epochSecondsAsUtc(raw['date']);
  if (date == null) return null;
  final numerator = _intOrNull(raw['numerator']);
  final denominator = _intOrNull(raw['denominator']);
  if (numerator == null ||
      denominator == null ||
      numerator <= 0 ||
      denominator <= 0) {
    return null;
  }
  final day = _day(date);
  final sourceKey = 'split:$symbol:$day';
  return MarketCorporateAction(
    id: '$_source:$_dataset:$sourceKey',
    source: _source,
    dataset: _dataset,
    sourceKey: sourceKey,
    revisionHash: _hash('$sourceKey|$numerator|$denominator'),
    identityStrength: MarketCorporateActionIdentityStrength.strong,
    symbol: symbol,
    market: market,
    kind: MarketCorporateActionKind.split,
    status: MarketCorporateActionStatus.unknown,
    exDate: date,
    splitNumerator: numerator,
    splitDenominator: denominator,
  );
}

DateTime? _epochSecondsAsUtc(Object? raw) {
  final value = _intOrNull(raw);
  if (value == null || value <= 0) return null;
  final utc = DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  return DateTime.utc(utc.year, utc.month, utc.day);
}

Decimal? _decimal(Object? raw) {
  if (raw is num) return Decimal.tryParse(raw.toString());
  if (raw is String) return Decimal.tryParse(raw);
  return null;
}

int? _intOrNull(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

String _day(DateTime value) => value.toUtc().toIso8601String().substring(0, 10);

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
