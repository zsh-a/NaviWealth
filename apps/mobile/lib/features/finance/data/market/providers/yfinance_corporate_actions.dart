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

class YahooCorporateActionParseResult {
  YahooCorporateActionParseResult({
    required Iterable<MarketCorporateAction> actions,
    required this.envelopeValid,
    required this.droppedRows,
    this.errorMessage,
  }) : actions = List<MarketCorporateAction>.unmodifiable(actions);

  final List<MarketCorporateAction> actions;
  final bool envelopeValid;
  final int droppedRows;
  final String? errorMessage;
}

List<MarketCorporateAction> parseYahooMarketCorporateActions({
  required Map<String, Object?> responseBody,
  required String symbol,
  required String currency,
  required AssetMarket market,
}) => parseYahooMarketCorporateActionsDetailed(
  responseBody: responseBody,
  symbol: symbol,
  currency: currency,
  market: market,
).actions;

YahooCorporateActionParseResult parseYahooMarketCorporateActionsDetailed({
  required Map<String, Object?> responseBody,
  required String symbol,
  required String currency,
  required AssetMarket market,
}) {
  final chart = responseBody['chart'];
  if (chart is! Map) {
    return YahooCorporateActionParseResult(
      actions: const [],
      envelopeValid: false,
      droppedRows: 0,
      errorMessage: 'chart response is missing chart object',
    );
  }
  if (chart['error'] != null) {
    return YahooCorporateActionParseResult(
      actions: const [],
      envelopeValid: false,
      droppedRows: 0,
      errorMessage: 'chart response contains provider error',
    );
  }
  final results = chart['result'];
  if (results is! List) {
    return YahooCorporateActionParseResult(
      actions: const [],
      envelopeValid: false,
      droppedRows: 0,
      errorMessage: 'chart.result is not a list',
    );
  }
  if (results.isEmpty) {
    return YahooCorporateActionParseResult(
      actions: const [],
      envelopeValid: true,
      droppedRows: 0,
    );
  }
  final first = results.first;
  if (first is! Map) {
    return YahooCorporateActionParseResult(
      actions: const [],
      envelopeValid: false,
      droppedRows: 0,
      errorMessage: 'chart.result first item is not an object',
    );
  }
  final events = first['events'];
  if (events == null) {
    return YahooCorporateActionParseResult(
      actions: const [],
      envelopeValid: true,
      droppedRows: 0,
    );
  }
  if (events is! Map) {
    return YahooCorporateActionParseResult(
      actions: const [],
      envelopeValid: false,
      droppedRows: 0,
      errorMessage: 'chart events block is not an object',
    );
  }

  final upperSymbol = symbol.toUpperCase();
  final upperCurrency = currency.toUpperCase();
  final out = <MarketCorporateAction>[];
  var droppedRows = 0;

  final dividends = events['dividends'];
  if (dividends != null && dividends is! Map) {
    droppedRows++;
  } else if (dividends is Map) {
    for (final entry in dividends.entries) {
      final event = _parseDividend(
        entry.value,
        providerEventKey: entry.key.toString(),
        symbol: upperSymbol,
        currency: upperCurrency,
        market: market,
      );
      if (event == null) {
        droppedRows++;
      } else {
        out.add(event);
      }
    }
  }

  final splits = events['splits'];
  if (splits != null && splits is! Map) {
    droppedRows++;
  } else if (splits is Map) {
    for (final entry in splits.entries) {
      final event = _parseSplit(
        entry.value,
        providerEventKey: entry.key.toString(),
        symbol: upperSymbol,
        market: market,
      );
      if (event == null) {
        droppedRows++;
      } else {
        out.add(event);
      }
    }
  }

  return YahooCorporateActionParseResult(
    actions: out,
    envelopeValid: true,
    droppedRows: droppedRows,
  );
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

MarketCorporateAction? _parseDividend(
  Object? raw, {
  required String providerEventKey,
  required String symbol,
  required String currency,
  required AssetMarket market,
}) {
  if (raw is! Map) return null;
  final date = _epochSecondsAsUtc(raw['date']);
  final amount = _decimal(raw['amount']);
  if (date == null || amount == null || amount < Decimal.zero) return null;
  final day = _day(date);
  final eventKey = _hash(providerEventKey).substring(0, 12);
  final sourceKey = 'div:$symbol:$day:$eventKey';
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
  Object? raw, {
  required String providerEventKey,
  required String symbol,
  required AssetMarket market,
}) {
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
  final eventKey = _hash(providerEventKey).substring(0, 12);
  final sourceKey = 'split:$symbol:$day:$eventKey';
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
