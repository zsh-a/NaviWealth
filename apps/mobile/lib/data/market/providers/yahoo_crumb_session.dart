import 'dart:async';

import 'package:dio/dio.dart';

import '../exceptions.dart';

/// Holds the cookie jar + crumb token Yahoo Finance requires for its
/// `query[12].finance.yahoo.com` endpoints since the mid-2023 EU consent
/// rollout.
///
/// Mirrors the dance the Python `yfinance` library does:
///
/// 1. GET `https://fc.yahoo.com/` (or `https://finance.yahoo.com/` as
///    fallback) to receive `Set-Cookie` headers — the response status is
///    irrelevant, only the cookies matter.
/// 2. GET `https://query1.finance.yahoo.com/v1/test/getcrumb` with those
///    cookies; the body is the plain-text crumb token.
/// 3. Future data requests append `?crumb=<token>` and forward the same
///    `Cookie` header.
///
/// The session caches both for the app lifetime and only refreshes on
/// explicit [invalidate], typically triggered by a 401 from a data call.
/// Concurrent [ensureReady] calls coalesce on a single refresh future.
///
/// IMPORTANT — Dio gotcha: when you pass a manually-constructed
/// [RequestOptions] to `dio.fetch`, none of the `BaseOptions` (validateStatus,
/// headers, timeouts) are merged in. Every request below therefore sets
/// these fields explicitly via [_buildOptions]; setting them on `BaseOptions`
/// would silently do nothing.
class YahooCrumbSession {
  YahooCrumbSession({Dio? dio}) : _dio = dio ?? Dio();

  // Real Safari UA matches what `yfinance` (Python) ships. Yahoo flags
  // anything with an app-name suffix as a bot and serves 401 / 429 to it,
  // so this string deliberately looks like an ordinary browser.
  static const userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) '
      'Version/16.5 Safari/605.1.15';

  /// Shared browser-like headers any caller hitting `query[12].finance.yahoo.com`
  /// should send. Yahoo's options endpoint is particularly picky and
  /// returns 401 / 429 to clients that omit any of these.
  static Map<String, String> browserHeaders() => const {
    'User-Agent': userAgent,
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.5',
    'Accept-Encoding': 'gzip, deflate',
    'Connection': 'keep-alive',
  };
  static const _primaryPrimingUrl = 'https://fc.yahoo.com/';
  static const _fallbackPrimingUrl = 'https://finance.yahoo.com/';
  // yfinance v0.2.40+ moved getcrumb to query1; query2 still works but
  // gets harsher per-IP throttling.
  static const _crumbUrl = 'https://query1.finance.yahoo.com/v1/test/getcrumb';

  static const _requestTimeout = Duration(seconds: 8);

  final Dio _dio;
  final Map<String, String> _cookies = {};
  String? _crumb;
  Future<void>? _refreshing;

  /// Current crumb, or `null` if [ensureReady] hasn't completed.
  String? get crumb => _crumb;

  /// `Cookie` header value built from the current jar, or `null` when
  /// empty. Callers that always want a header (even if empty) should
  /// coalesce to `''`.
  String? get cookieHeader => _cookies.isEmpty
      ? null
      : _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Ensures cookies + crumb are populated. Concurrent calls share one
  /// refresh future so a burst of options scans doesn't fire N priming
  /// requests in parallel.
  Future<void> ensureReady() {
    if (_crumb != null) return Future.value();
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  /// Drops the cached crumb + cookies so the next [ensureReady] does a
  /// full re-handshake. Call from a 401 retry path.
  void invalidate() {
    _crumb = null;
    _cookies.clear();
  }

  Future<void> _refresh() async {
    await _prime(_primaryPrimingUrl);
    if (_cookies.isEmpty) await _prime(_fallbackPrimingUrl);
    if (_cookies.isEmpty) {
      throw const ProviderResponseException(
        'yahoo crumb: failed to obtain session cookies',
        provider: 'yahoo_crumb',
      );
    }
    final crumb = await _fetchCrumb();
    if (crumb.isEmpty) {
      throw const ProviderResponseException(
        'yahoo crumb: empty crumb response',
        provider: 'yahoo_crumb',
      );
    }
    _crumb = crumb;
  }

  Future<void> _prime(String url) async {
    try {
      final resp = await _dio.fetch<dynamic>(_buildOptions(path: url));
      _ingestSetCookie(resp.headers.map['set-cookie']);
    } on DioException catch (e) {
      // validateStatus accepts everything, so we should only get here on
      // transport-level failures. Cookies on the failing response are
      // still useful when the body itself is fine.
      final headers = e.response?.headers.map['set-cookie'];
      if (headers != null) _ingestSetCookie(headers);
    }
  }

  Future<String> _fetchCrumb() async {
    final extraHeaders = <String, String>{};
    final cookie = cookieHeader;
    if (cookie != null) extraHeaders['Cookie'] = cookie;
    final resp = await _dio.fetch<dynamic>(
      _buildOptions(
        path: _crumbUrl,
        responseType: ResponseType.plain,
        extraHeaders: extraHeaders,
      ),
    );
    final status = resp.statusCode;
    if (status == 429) {
      throw RateLimitException(
        'yahoo crumb: rate-limited',
        provider: 'yahoo_crumb',
        retryAfter: _parseRetryAfter(resp.headers.value('retry-after')),
      );
    }
    if (status != 200) {
      throw ProviderUnavailableException(
        'yahoo crumb: getcrumb http $status',
        provider: 'yahoo_crumb',
        statusCode: status,
      );
    }
    final body = resp.data;
    final text = body is String ? body : body?.toString() ?? '';
    return text.trim();
  }

  /// Builds a fully-specified RequestOptions because `dio.fetch` does not
  /// merge BaseOptions when given a hand-built request — see class doc.
  /// Browser-like headers are critical: Yahoo serves 401 / 429 to clients
  /// that omit Accept or send a UA with an app-name suffix.
  RequestOptions _buildOptions({
    required String path,
    ResponseType responseType = ResponseType.json,
    Map<String, String>? extraHeaders,
  }) {
    final headers = Map<String, String>.from(browserHeaders());
    if (extraHeaders != null) headers.addAll(extraHeaders);
    return RequestOptions(
      path: path,
      method: 'GET',
      responseType: responseType,
      followRedirects: true,
      connectTimeout: _requestTimeout,
      receiveTimeout: _requestTimeout,
      validateStatus: (_) => true,
      headers: headers,
    );
  }

  void _ingestSetCookie(List<String>? rawHeaders) {
    if (rawHeaders == null) return;
    for (final raw in rawHeaders) {
      final parsed = _parseSetCookie(raw);
      if (parsed != null) _cookies[parsed.$1] = parsed.$2;
    }
  }

  /// Parses the first `name=value` pair out of a `Set-Cookie` header,
  /// ignoring attributes (Path, Domain, Expires, …). Returns `null` for
  /// malformed entries — Yahoo occasionally emits ones with only a name.
  (String, String)? _parseSetCookie(String raw) {
    final firstPair = raw.split(';').first.trim();
    final eq = firstPair.indexOf('=');
    if (eq <= 0 || eq == firstPair.length - 1) return null;
    final name = firstPair.substring(0, eq).trim();
    final value = firstPair.substring(eq + 1).trim();
    if (name.isEmpty) return null;
    return (name, value);
  }

  Duration? _parseRetryAfter(String? header) {
    if (header == null) return null;
    final secs = int.tryParse(header.trim());
    if (secs != null) return Duration(seconds: secs);
    final at = DateTime.tryParse(header);
    if (at != null) {
      final diff = at.toUtc().difference(DateTime.now().toUtc());
      return diff.isNegative ? Duration.zero : diff;
    }
    return null;
  }
}
