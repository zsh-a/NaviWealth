part of 'yfinance_options_provider.dart';

mixin YFinanceOptionsParsingMixin on YFinanceOptionsNormalizationMixin {
  Clock get _clock;

  String get name;

  Future<Response<Map<String, dynamic>>> _sendAuthed(
    String symbol, {
    int? expirationEpoch,
  });

  Future<_RawChain> _fetchOnce(String symbol, {int? expirationEpoch}) async {
    final response = await _sendAuthed(
      symbol,
      expirationEpoch: expirationEpoch,
    );
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw ProviderResponseException(
        'options response not an object',
        provider: name,
      );
    }
    final envelope = body['optionChain'];
    if (envelope is! Map<String, dynamic>) {
      throw ProviderResponseException(
        'optionChain envelope missing',
        provider: name,
      );
    }
    final err = envelope['error'];
    if (err is Map<String, dynamic>) {
      final code = (err['code'] as String?) ?? 'unknown';
      final desc = (err['description'] as String?) ?? '';
      if (code.toLowerCase().contains('not')) {
        throw SymbolNotFoundException('$symbol: $desc', provider: name);
      }
      throw ProviderResponseException('$code: $desc', provider: name);
    }
    final results = (envelope['result'] as List?) ?? const [];
    if (results.isEmpty) {
      throw SymbolNotFoundException(
        '$symbol returned no option chain result',
        provider: name,
      );
    }
    final result = _expectMap(
      results.first,
      'optionChain.result[0]',
      provider: name,
    );
    final quote = _expectMap(result['quote'], 'quote', provider: name);
    final currency = (quote['currency'] as String?)?.toUpperCase() ?? 'USD';
    final underlyingPriceRaw =
        (quote['regularMarketPrice'] as num?)?.toString() ??
        (quote['ask'] as num?)?.toString() ??
        (quote['bid'] as num?)?.toString();
    if (underlyingPriceRaw == null) {
      throw ProviderResponseException(
        'quote.regularMarketPrice missing for $symbol',
        provider: name,
      );
    }

    final expirations = ((result['expirationDates'] as List?) ?? const [])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList();
    final options = (result['options'] as List?) ?? const [];
    final contracts = <OptionContract>[];
    int? firstExpirationEpoch;
    if (options.isNotEmpty) {
      final expSlice = _expectMap(options.first, 'options[0]', provider: name);
      final expEpoch = (expSlice['expirationDate'] as num?)?.toInt();
      firstExpirationEpoch = expEpoch;
      final expiration = expEpoch == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expEpoch * 1000, isUtc: true);
      if (expiration != null) {
        final calls = ((expSlice['calls'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>();
        final puts = ((expSlice['puts'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>();
        final callRows = calls.toList(growable: false);
        final putRows = puts.toList(growable: false);
        _logRawSliceDiagnostics(
          symbol: symbol,
          expiration: expiration,
          calls: callRows,
          puts: putRows,
        );
        final underlyingMoney = Money.parse(underlyingPriceRaw, currency);
        for (final raw in callRows) {
          final c = _normalize(
            raw: raw,
            type: OptionType.call,
            underlying: symbol,
            currency: currency,
            expiration: expiration,
            underlyingPrice: underlyingMoney,
            fetchedAt: _clock.now().toUtc(),
          );
          if (c != null) contracts.add(c);
        }
        for (final raw in putRows) {
          final c = _normalize(
            raw: raw,
            type: OptionType.put,
            underlying: symbol,
            currency: currency,
            expiration: expiration,
            underlyingPrice: underlyingMoney,
            fetchedAt: _clock.now().toUtc(),
          );
          if (c != null) contracts.add(c);
        }
      }
    }
    return _RawChain(
      currency: currency,
      underlyingPriceRaw: underlyingPriceRaw,
      expirations: expirations,
      firstExpirationEpoch: firstExpirationEpoch,
      contracts: contracts,
    );
  }

  void _logRawSliceDiagnostics({
    required String symbol,
    required DateTime expiration,
    required List<Map<String, dynamic>> calls,
    required List<Map<String, dynamic>> puts,
  }) {
    final rows = [...calls, ...puts];
    final positiveBid = rows.where((r) => _safeNum(r['bid']) > 0).length;
    final positiveAsk = rows.where((r) => _safeNum(r['ask']) > 0).length;
    final positiveLast = rows.where((r) => _safeNum(r['lastPrice']) > 0).length;
    final positiveOi = rows
        .where((r) => _safeNum(r['openInterest']) > 0)
        .length;
    final positiveVolume = rows.where((r) => _safeNum(r['volume']) > 0).length;
    final samples = rows.take(3).map(_rawSample).join(' | ');
    AppLogger.instance.d(
      'options-income yfinance: raw slice '
      '$symbol exp=${expiration.toIso8601String().substring(0, 10)} '
      'calls=${calls.length} puts=${puts.length} '
      'positiveBid=$positiveBid/${rows.length} '
      'positiveAsk=$positiveAsk/${rows.length} '
      'positiveLast=$positiveLast/${rows.length} '
      'positiveOI=$positiveOi/${rows.length} '
      'positiveVolume=$positiveVolume/${rows.length} '
      'samples=$samples',
    );
  }

  String _rawSample(Map<String, dynamic> raw) {
    return [
      raw['contractSymbol'] ?? '?',
      'strike=${raw['strike']}',
      'bid=${raw['bid']}',
      'ask=${raw['ask']}',
      'last=${raw['lastPrice']}',
      'oi=${raw['openInterest']}',
      'vol=${raw['volume']}',
    ].join(' ');
  }
}
