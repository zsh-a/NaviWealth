import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/market/exceptions.dart';
import 'package:naviwealth/features/finance/data/market/providers/yahoo_crumb_session.dart';

import '../canned_adapter.dart';

YahooCrumbSession _makeSession(CannedAdapter adapter) {
  final dio = Dio(BaseOptions(validateStatus: (_) => true))
    ..httpClientAdapter = adapter;
  return YahooCrumbSession(dio: dio);
}

void main() {
  group('YahooCrumbSession.ensureReady', () {
    test(
      'captures Set-Cookie from priming response and fetches crumb',
      () async {
        final adapter = CannedAdapter()
          ..enqueueRaw(
            'fc.yahoo.com',
            CannedResponse(
              'irrelevant',
              status: 404,
              headers: {
                'set-cookie': ['A1=cookie1; Domain=.yahoo.com; Path=/'],
                Headers.contentTypeHeader: ['text/html'],
              },
            ),
          )
          ..enqueueRaw(
            'getcrumb',
            CannedResponse(
              'TEST_CRUMB_42',
              status: 200,
              headers: const {
                Headers.contentTypeHeader: ['text/plain'],
              },
            ),
          );

        final session = _makeSession(adapter);
        await session.ensureReady();

        expect(session.crumb, 'TEST_CRUMB_42');
        expect(session.cookieHeader, 'A1=cookie1');
      },
    );

    test(
      'falls back to finance.yahoo.com when fc.yahoo.com has no cookies',
      () async {
        final adapter = CannedAdapter()
          ..enqueueRaw(
            'fc.yahoo.com',
            CannedResponse(
              '',
              status: 404,
              headers: const {
                Headers.contentTypeHeader: ['text/html'],
              },
            ),
          )
          ..enqueueRaw(
            'finance.yahoo.com',
            CannedResponse(
              '<html></html>',
              status: 200,
              headers: {
                'set-cookie': ['A3=fallback; Domain=.yahoo.com'],
                Headers.contentTypeHeader: ['text/html'],
              },
            ),
          )
          ..enqueueRaw(
            'getcrumb',
            CannedResponse(
              'FALLBACK_CRUMB',
              status: 200,
              headers: const {
                Headers.contentTypeHeader: ['text/plain'],
              },
            ),
          );

        final session = _makeSession(adapter);
        await session.ensureReady();

        expect(session.cookieHeader, 'A3=fallback');
        expect(session.crumb, 'FALLBACK_CRUMB');
      },
    );

    test(
      'throws ProviderResponseException when no cookies are obtained',
      () async {
        final adapter = CannedAdapter()
          ..enqueueRaw(
            'fc.yahoo.com',
            CannedResponse(
              '',
              status: 404,
              headers: const {
                Headers.contentTypeHeader: ['text/html'],
              },
            ),
          )
          ..enqueueRaw(
            'finance.yahoo.com',
            CannedResponse(
              '',
              status: 200,
              headers: const {
                Headers.contentTypeHeader: ['text/html'],
              },
            ),
          );

        final session = _makeSession(adapter);
        expect(
          () => session.ensureReady(),
          throwsA(isA<ProviderResponseException>()),
        );
      },
    );

    test('coalesces concurrent ensureReady calls', () async {
      final adapter = CannedAdapter()
        ..enqueueRaw(
          'fc.yahoo.com',
          CannedResponse(
            '',
            status: 404,
            headers: {
              'set-cookie': ['A1=concurrent'],
              Headers.contentTypeHeader: ['text/html'],
            },
          ),
        )
        ..enqueueRaw(
          'getcrumb',
          CannedResponse(
            'CONC_CRUMB',
            status: 200,
            headers: const {
              Headers.contentTypeHeader: ['text/plain'],
            },
          ),
        );

      final session = _makeSession(adapter);
      await Future.wait([session.ensureReady(), session.ensureReady()]);

      // Only the first ensureReady should have hit each endpoint.
      final fcCalls = adapter.calls
          .where((c) => c.uri.host == 'fc.yahoo.com')
          .length;
      final crumbCalls = adapter.calls
          .where((c) => c.uri.path.contains('getcrumb'))
          .length;
      expect(fcCalls, 1);
      expect(crumbCalls, 1);
    });
  });

  group('YahooCrumbSession outbound headers', () {
    test('sends browser-like UA + Accept headers on getcrumb (Dio BaseOptions '
        'do not merge into hand-built RequestOptions — every request must '
        'carry the headers explicitly)', () async {
      final adapter = CannedAdapter()
        ..enqueueRaw(
          'fc.yahoo.com',
          CannedResponse(
            '',
            status: 404,
            headers: {
              'set-cookie': ['A1=hdrtest'],
              Headers.contentTypeHeader: ['text/html'],
            },
          ),
        )
        ..enqueueRaw(
          'getcrumb',
          CannedResponse(
            'HEADERCRUMB',
            status: 200,
            headers: const {
              Headers.contentTypeHeader: ['text/plain'],
            },
          ),
        );

      final session = _makeSession(adapter);
      await session.ensureReady();

      final crumbCall = adapter.calls.firstWhere(
        (c) => c.uri.path.contains('getcrumb'),
      );
      final ua = crumbCall.headers['User-Agent'] as String?;
      expect(ua, isNotNull);
      expect(ua, contains('Safari'));
      expect(ua, isNot(contains('NaviWealth')));
      expect(crumbCall.headers['Accept'], '*/*');
      expect(crumbCall.headers['Accept-Language'], isNotNull);
      expect(crumbCall.headers['Cookie'], 'A1=hdrtest');
    });

    test('surfaces 429 from getcrumb as RateLimitException', () async {
      final adapter = CannedAdapter()
        ..enqueueRaw(
          'fc.yahoo.com',
          CannedResponse(
            '',
            status: 404,
            headers: {
              'set-cookie': ['A1=rl'],
              Headers.contentTypeHeader: ['text/html'],
            },
          ),
        )
        ..enqueueRaw(
          'getcrumb',
          CannedResponse(
            'rate-limited',
            status: 429,
            headers: const {
              Headers.contentTypeHeader: ['text/plain'],
              'retry-after': ['30'],
            },
          ),
        );

      final session = _makeSession(adapter);
      expect(
        () => session.ensureReady(),
        throwsA(
          isA<RateLimitException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 30),
          ),
        ),
      );
    });
  });

  group('YahooCrumbSession.invalidate', () {
    test(
      'drops state so the next ensureReady reissues the handshake',
      () async {
        final adapter = CannedAdapter()
          ..enqueueRaw(
            'fc.yahoo.com',
            CannedResponse(
              '',
              status: 404,
              headers: {
                'set-cookie': ['A1=first'],
                Headers.contentTypeHeader: ['text/html'],
              },
            ),
          )
          ..enqueueRaw(
            'getcrumb',
            CannedResponse(
              'CRUMB_FIRST',
              status: 200,
              headers: const {
                Headers.contentTypeHeader: ['text/plain'],
              },
            ),
          )
          ..enqueueRaw(
            'fc.yahoo.com',
            CannedResponse(
              '',
              status: 404,
              headers: {
                'set-cookie': ['A1=second'],
                Headers.contentTypeHeader: ['text/html'],
              },
            ),
          )
          ..enqueueRaw(
            'getcrumb',
            CannedResponse(
              'CRUMB_SECOND',
              status: 200,
              headers: const {
                Headers.contentTypeHeader: ['text/plain'],
              },
            ),
          );

        final session = _makeSession(adapter);
        await session.ensureReady();
        expect(session.crumb, 'CRUMB_FIRST');

        session.invalidate();
        await session.ensureReady();
        expect(session.crumb, 'CRUMB_SECOND');
        expect(session.cookieHeader, 'A1=second');
      },
    );
  });
}
