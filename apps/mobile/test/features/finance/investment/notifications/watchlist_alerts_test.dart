import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/notifications/notification_service.dart';
import 'package:naviwealth/core/notifications/providers.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_providers.dart';
import 'package:naviwealth/features/finance/investment/data/watchlist_repository.dart';
import 'package:naviwealth/features/finance/investment/notifications/watchlist_alerts.dart';
import 'package:naviwealth/features/finance/market/domain/asset_market.dart';
import 'package:naviwealth/features/finance/market/domain/market_data_service.dart';
import 'package:naviwealth/features/finance/market/domain/quote.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _sync = SyncMeta(
  ownerUserId: 'u',
  updatedAt: DateTime.utc(2026, 7, 19),
  updatedByDevice: 'test',
  hlc: Hlc.zero('test'),
);

WatchlistItem _item({Decimal? above, Decimal? below, bool enabled = true}) =>
    WatchlistItem(
      id: 'us_stock:AAPL',
      symbol: 'AAPL',
      market: AssetMarket.usStock,
      addedAt: DateTime.utc(2026, 7, 19),
      alertRules: PriceAlertRules(enabled: enabled, above: above, below: below),
      sync: _sync,
    );

WatchlistQuoteSnapshot _snapshot(
  WatchlistItem item,
  String price, {
  DataFreshness freshness = DataFreshness.live,
  DateTime? asOf,
  String? symbol,
}) => WatchlistQuoteSnapshot(
  item: item,
  response: MarketResponse(
    data: Quote(
      symbol: symbol ?? item.symbol,
      currency: 'USD',
      price: Decimal.parse(price),
      previousClose: Decimal.parse('200'),
      asOf: asOf ?? DateTime.utc(2026, 7, 19, 2),
    ),
    freshness: freshness,
    source: 'test',
    fetchedAt: DateTime.utc(2026, 7, 19, 2),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('evaluateWatchlistAlerts', () {
    test('ignores stale, future-dated and mismatched quotes', () {
      final item = _item(above: Decimal.parse('200'));
      expect(
        evaluateWatchlistAlerts(
          snapshots: [
            _snapshot(item, '201', freshness: DataFreshness.stale),
            _snapshot(item, '201', asOf: DateTime.utc(2099)),
            _snapshot(item, '201', symbol: 'MSFT'),
          ],
          l10n: l10n,
          alreadyFired: {},
        ),
        isEmpty,
      );
    });

    test('separates owners and re-armed rule revisions', () {
      final item = _item(above: Decimal.parse('200'));
      List<WatchlistAlertEvent> evaluate(
        WatchlistItem item,
        Set<String> fired,
      ) => evaluateWatchlistAlerts(
        snapshots: [_snapshot(item, '201')],
        l10n: l10n,
        alreadyFired: fired,
      );
      final fired = {evaluate(item, {}).single.signature};
      for (final meta in [
        SyncMeta(
          ownerUserId: 'another-user',
          updatedAt: _sync.updatedAt,
          updatedByDevice: 'test',
          hlc: _sync.hlc,
        ),
        SyncMeta(
          ownerUserId: _sync.ownerUserId,
          updatedAt: _sync.updatedAt,
          updatedByDevice: 'another-device',
          hlc: Hlc.zero('another-device'),
        ),
      ]) {
        final other = WatchlistItem(
          id: item.id,
          symbol: item.symbol,
          market: item.market,
          addedAt: item.addedAt,
          alertRules: item.alertRules,
          sync: meta,
        );
        expect(evaluate(other, fired), hasLength(1));
      }
    });
    test('fires when the price crosses above the configured level', () {
      final events = evaluateWatchlistAlerts(
        snapshots: [_snapshot(_item(above: Decimal.parse('200')), '201.25')],
        l10n: l10n,
        alreadyFired: const <String>{},
      );

      expect(events, hasLength(1));
      expect(events.single.message, contains('AAPL'));
      expect(events.single.signature, contains('above'));
    });

    test('fires when the price drops to the configured floor', () {
      final events = evaluateWatchlistAlerts(
        snapshots: [_snapshot(_item(below: Decimal.parse('200')), '195')],
        l10n: l10n,
        alreadyFired: const <String>{},
      );

      expect(events, hasLength(1));
      expect(events.single.signature, contains('below'));
    });

    test('stays quiet while the price is inside the band', () {
      final events = evaluateWatchlistAlerts(
        snapshots: [
          _snapshot(
            _item(above: Decimal.parse('210'), below: Decimal.parse('190')),
            '201.25',
          ),
        ],
        l10n: l10n,
        alreadyFired: const <String>{},
      );

      expect(events, isEmpty);
    });

    test('never re-fires a rule that already reached the user', () {
      final snapshot = _snapshot(_item(above: Decimal.parse('200')), '201.25');
      final first = evaluateWatchlistAlerts(
        snapshots: [snapshot],
        l10n: l10n,
        alreadyFired: const <String>{},
      );
      final second = evaluateWatchlistAlerts(
        snapshots: [snapshot],
        l10n: l10n,
        alreadyFired: {first.single.signature},
      );

      expect(first, hasLength(1));
      expect(second, isEmpty);
    });

    test('ignores disabled rules, ruleless items and unpriced quotes', () {
      final events = evaluateWatchlistAlerts(
        snapshots: [
          _snapshot(
            _item(above: Decimal.parse('200'), enabled: false),
            '201.25',
          ),
          _snapshot(_item(), '201.25'),
          WatchlistQuoteSnapshot(
            item: _item(above: Decimal.parse('200')),
            error: StateError('offline'),
          ),
        ],
        l10n: l10n,
        alreadyFired: const <String>{},
      );

      expect(events, isEmpty);
    });
  });

  group('WatchlistAlertLedger', () {
    test('remembers fired signatures across reads', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ledger = WatchlistAlertLedger(
        await SharedPreferences.getInstance(),
      );

      expect(ledger.read(), isEmpty);
      await ledger.remember({'us_stock:AAPL|above|200'});
      await ledger.remember({'us_stock:MSFT|below|100'});

      expect(ledger.read(), {
        'us_stock:AAPL|above|200',
        'us_stock:MSFT|below|100',
      });
    });

    test('can be cleared so a rule may announce again', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ledger = WatchlistAlertLedger(
        await SharedPreferences.getInstance(),
      );

      await ledger.remember({'us_stock:AAPL|above|200'});
      await ledger.clear();

      expect(ledger.read(), isEmpty);
    });

    test('bounds its own growth on a long-lived install', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final ledger = WatchlistAlertLedger(preferences);

      for (var index = 0; index < 200; index++) {
        await ledger.remember({'rule-$index'});
      }

      final stored = preferences.getStringList(
        'naviwealth.finance.watchlist.alerts.fired',
      );
      expect(stored, isNotNull);
      expect(stored!.length, lessThanOrEqualTo(128));
      // The most recent rules survive the trim.
      expect(ledger.read(), contains('rule-199'));
      expect(ledger.read(), isNot(contains('rule-71')));
      expect(ledger.read(), contains('rule-72'));
    });
  });

  group('watchlistAlertNotificationId', () {
    test('is stable for one signature and positive', () {
      const signature = 'us_stock:AAPL|above|200';

      expect(
        watchlistAlertNotificationId(signature),
        watchlistAlertNotificationId(signature),
      );
      expect(watchlistAlertNotificationId(signature), greaterThan(0));
    });

    test('separates distinct rules', () {
      expect(
        watchlistAlertNotificationId('us_stock:AAPL|above|200'),
        isNot(watchlistAlertNotificationId('us_stock:AAPL|below|200')),
      );
    });
  });

  group('delivery', () {
    late SharedPreferences preferences;
    late _Notifications notifications;
    late ProviderContainer container;
    late WatchlistAlertMonitor monitor;
    final snapshot = _snapshot(_item(above: Decimal.parse('200')), '201');

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = await SharedPreferences.getInstance();
      notifications = _Notifications();
      final monitorProvider = Provider<WatchlistAlertMonitor>((ref) {
        final result = WatchlistAlertMonitor(ref);
        ref.onDispose(result.stop);
        return result;
      });
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          notificationServiceProvider.overrideWithValue(notifications),
        ],
      );
      monitor = container.read(monitorProvider);
    });
    tearDown(() => container.dispose());

    test(
      'does not consume reminders with no permission and no presenter',
      () async {
        notifications.permission = false;
        await monitor.dispatch([snapshot]);
        expect(WatchlistAlertLedger(preferences).read(), isEmpty);
        final received = <WatchlistAlertEvent>[];
        final subscription = monitor.fallbacks.listen((event) {
          received.add(event);
          unawaited(monitor.acknowledge(event));
        });
        addTearDown(subscription.cancel);
        await monitor.dispatch([snapshot]);
        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(1));
        expect(WatchlistAlertLedger(preferences).read(), hasLength(1));
        expect(await monitor.dispatch([snapshot]), isEmpty);
      },
    );

    test(
      'retries after system delivery fails, then deduplicates success',
      () async {
        notifications.fail = true;
        await monitor.dispatch([snapshot]);
        expect(WatchlistAlertLedger(preferences).read(), isEmpty);
        notifications.fail = false;
        await Future.wait([
          monitor.dispatch([snapshot]),
          monitor.dispatch([snapshot]),
        ]);
        expect(notifications.delivered, 1);
        expect(WatchlistAlertLedger(preferences).read(), hasLength(1));
      },
    );

    test('does not evaluate while the app is backgrounded', () async {
      monitor.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(await monitor.dispatch([snapshot]), isEmpty);
      expect(notifications.delivered, 0);
      monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await monitor.dispatch([snapshot]);
      expect(notifications.delivered, 1);
    });

    test('safely stops during an async permission check', () async {
      final permission = Completer<bool>();
      notifications.permissionCheck = permission.future;
      final dispatched = monitor.dispatch([snapshot]);
      monitor.stop();
      permission.complete(false);
      await dispatched;
      expect(WatchlistAlertLedger(preferences).read(), isEmpty);
    });
  });
}

class _Notifications implements NotificationService {
  bool permission = true;
  bool fail = false;
  int delivered = 0;
  Future<bool>? permissionCheck;

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<bool> hasPermissions() async => permissionCheck ?? permission;
  @override
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    required NotificationChannelSpec channel,
    String? payload,
  }) async {
    if (fail) throw StateError('notifications unavailable');
    delivered++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
