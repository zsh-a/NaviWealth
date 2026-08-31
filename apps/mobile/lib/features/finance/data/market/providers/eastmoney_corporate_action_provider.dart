import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/http/market_http_client.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/corporate_action_provider.dart';
import 'package:naviwealth/features/finance/market/domain/market_corporate_action.dart';

/// A-share distribution-plan adapter based on Eastmoney's
/// `RPT_SHAREBONUS_DET` dataset.
///
/// Provider ratios and cash values are quoted per ten shares. This adapter
/// normalizes every value to a per-one-share Decimal at the provider boundary.
class EastmoneyCorporateActionProvider implements CorporateActionProvider {
  EastmoneyCorporateActionProvider({
    required MarketHttpClient http,
    this.available = true,
    DateTime Function()? now,
  }) : _http = http,
       _now = now ?? (() => DateTime.now().toUtc());

  final MarketHttpClient _http;
  final DateTime Function() _now;

  /// False for Flutter Web, where the upstream endpoint currently lacks a
  /// usable CORS contract.
  final bool available;

  static const String _baseUrl =
      'https://datacenter-web.eastmoney.com/api/data/v1/get';
  static const String _dataset = 'RPT_SHAREBONUS_DET';
  static const int _pageSize = 500;
  static const int _maxPages = 50;

  @override
  String get name => 'eastmoney';

  @override
  CorporateActionProviderCapabilities get capabilities =>
      const CorporateActionProviderCapabilities(
        supportedMarkets: {AssetMarket.cnA},
        supportsRecordDate: true,
        supportsPayDate: true,
        supportsRevisions: true,
        availableOnWeb: false,
      );

  @override
  Future<CorporateActionFetchResult> fetch(
    CorporateActionFetchRequest request,
  ) async {
    if (!available || !capabilities.supportedMarkets.contains(request.market)) {
      return CorporateActionFetchResult(
        provider: name,
        disposition: CorporateActionFetchDisposition.unsupported,
        actions: const [],
        fetchedAt: _now(),
      );
    }

    final symbol = request.symbol.trim().toUpperCase();
    if (!RegExp(r'^\d{6}$').hasMatch(symbol)) {
      throw SymbolNotFoundException(
        'Eastmoney dividend detail requires a six-digit A-share symbol',
        provider: name,
      );
    }

    final actions = <MarketCorporateAction>[];
    var page = 1;
    var pages = 1;
    var droppedRows = 0;
    do {
      final response = await _http.send<Object?>(
        RequestOptions(
          path: _baseUrl,
          method: 'GET',
          responseType: ResponseType.plain,
          queryParameters: <String, Object?>{
            'reportName': _dataset,
            'columns': 'ALL',
            'pageSize': _pageSize,
            'pageNumber': page,
            'source': 'WEB',
            'client': 'WEB',
            'sortColumns': 'REPORT_DATE',
            'sortTypes': '-1',
            'filter': '(SECURITY_CODE="$symbol")',
          },
        ),
        endpoint: 'corporateActions',
      );
      final body = _decodeBody(response.data);
      final result = body['result'];
      if (result == null) break;
      if (result is! Map) {
        throw const ProviderResponseException(
          'Eastmoney result is not an object',
          provider: 'eastmoney',
        );
      }
      pages = _integer(result['pages']) ?? 1;
      final data = result['data'];
      if (data is! List) {
        throw const ProviderResponseException(
          'Eastmoney result.data is not a list',
          provider: 'eastmoney',
        );
      }
      for (final raw in data) {
        if (raw is! Map) {
          droppedRows++;
          continue;
        }
        final row = raw.cast<String, Object?>();
        final rowSymbol = row['SECURITY_CODE']?.toString();
        if (rowSymbol != null && rowSymbol != symbol) {
          throw ProviderResponseException(
            'Eastmoney returned $rowSymbol for requested symbol $symbol',
            provider: name,
          );
        }
        final action = _mapRow(row, symbol);
        if (action == null) {
          droppedRows++;
          continue;
        }
        final timelineDate = action.timelineDate;
        if (timelineDate != null &&
            (timelineDate.isBefore(_dayFloor(request.from)) ||
                timelineDate.isAfter(_dayFloor(request.to)))) {
          continue;
        }
        actions.add(action);
      }
      page++;
    } while (page <= pages && page <= _maxPages);

    final truncated = pages > _maxPages;
    final partial = droppedRows > 0 || truncated;
    return CorporateActionFetchResult(
      provider: name,
      disposition: partial
          ? CorporateActionFetchDisposition.partial
          : actions.isEmpty
          ? CorporateActionFetchDisposition.authoritativeEmpty
          : CorporateActionFetchDisposition.success,
      actions: actions,
      fetchedAt: _now(),
      warning: partial
          ? 'Dropped $droppedRows malformed row(s)'
                '${truncated ? ' and truncated after $_maxPages pages' : ''}.'
          : null,
    );
  }

  Map<String, Object?> _decodeBody(Object? raw) {
    Object? decoded = raw;
    if (raw is String) {
      try {
        decoded = jsonDecode(raw);
      } on FormatException catch (error) {
        throw ProviderResponseException(
          'Eastmoney response is not JSON',
          provider: name,
          cause: error,
        );
      }
    }
    if (decoded is! Map) {
      throw ProviderResponseException(
        'Eastmoney response is not an object',
        provider: name,
      );
    }
    return decoded.cast<String, Object?>();
  }

  MarketCorporateAction? _mapRow(Map<String, Object?> row, String symbol) {
    final reportDate = _date(row['REPORT_DATE']);
    final planNoticeDate = _date(row['PLAN_NOTICE_DATE']);
    final publicationDate = _date(row['PUBLISH_DATE']);
    final announcementDate = publicationDate ?? planNoticeDate;
    final recordDate = _date(row['EQUITY_RECORD_DATE']);
    final exDate = _date(row['EX_DIVIDEND_DATE']);
    final payDate = _date(row['PAY_DATE']);
    final noticeDate = _date(row['NOTICE_DATE']);

    final cashPerShare = _perTen(row['PRETAX_BONUS_RMB']);
    final bonusRatio = _perTen(row['BONUS_RATIO']);
    final capitalizationRatio = _perTen(row['IT_RATIO']);
    final totalStockRatio = _perTen(row['BONUS_IT_RATIO']);
    final hasComponent = <Decimal?>[
      cashPerShare,
      bonusRatio,
      capitalizationRatio,
      totalStockRatio,
    ].any((value) => value != null && value > Decimal.zero);
    if (!hasComponent) return null;

    final description = _text(row['IMPL_PLAN_PROFILE']);
    final rawStatus = _text(row['ASSIGN_PROGRESS']);
    final identityDate = reportDate ?? announcementDate ?? noticeDate;
    final identityStrength = identityDate == null
        ? MarketCorporateActionIdentityStrength.weak
        : MarketCorporateActionIdentityStrength.strong;
    final identityPart = identityDate == null
        ? _hash('$symbol|${description ?? ''}')
        : _day(identityDate);
    final sourceKey = '$symbol:$identityPart';
    final revisionHash = _hash(
      <Object?>[
        sourceKey,
        rawStatus,
        reportDate,
        announcementDate,
        recordDate,
        exDate,
        payDate,
        cashPerShare,
        bonusRatio,
        capitalizationRatio,
        totalStockRatio,
        description,
      ].join('|'),
    );
    return MarketCorporateAction(
      id: '$name:$_dataset:$sourceKey',
      source: name,
      dataset: _dataset,
      sourceKey: sourceKey,
      revisionHash: revisionHash,
      identityStrength: identityStrength,
      symbol: symbol,
      market: AssetMarket.cnA,
      kind: MarketCorporateActionKind.distribution,
      status: _status(rawStatus),
      reportDate: reportDate,
      announcementDate: announcementDate,
      recordDate: recordDate,
      exDate: exDate,
      payDate: payDate,
      currency: 'CNY',
      cashPerShare: cashPerShare,
      bonusRatio: bonusRatio,
      capitalizationRatio: capitalizationRatio,
      totalStockDistributionRatio: totalStockRatio,
      note: description,
    );
  }
}

MarketCorporateActionStatus _status(String? raw) {
  if (raw == null) return MarketCorporateActionStatus.unknown;
  if (raw.contains('取消') || raw.contains('终止')) {
    return MarketCorporateActionStatus.cancelled;
  }
  if (raw.contains('实施')) return MarketCorporateActionStatus.implemented;
  if (raw.contains('股东大会')) return MarketCorporateActionStatus.approved;
  if (raw.contains('预案') || raw.contains('董事会')) {
    return MarketCorporateActionStatus.proposed;
  }
  return MarketCorporateActionStatus.unknown;
}

Decimal? _perTen(Object? raw) {
  final value = _decimal(raw);
  if (value == null || value < Decimal.zero) return null;
  return (value / Decimal.fromInt(10)).toDecimal();
}

Decimal? _decimal(Object? raw) {
  if (raw is num) return Decimal.tryParse(raw.toString());
  if (raw is String) return Decimal.tryParse(raw.trim());
  return null;
}

int? _integer(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

DateTime? _date(Object? raw) {
  final value = raw?.toString();
  if (value == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

String? _text(Object? raw) {
  final value = raw?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

DateTime _dayFloor(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

String _day(DateTime value) => value.toUtc().toIso8601String().substring(0, 10);

String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
