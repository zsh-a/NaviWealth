import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_bridge.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_foreground_refresh.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_sync_controller.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_sync_status_store.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_token_store.dart';
import 'package:naviwealth/features/health/data/providers.dart';
import 'package:naviwealth/src/rust/api/health.dart' as rust;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

final _owner = StateProvider<String>((ref) => 'owner-a');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ProviderContainer container;
  late SharedPreferences prefs;
  late _Api api;
  late DateTime now;
  late GarminTokenStore tokens;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tokens = GarminTokenStore();
    await tokens.saveSession(
      ownerUserId: 'owner-a',
      region: GarminRegion.china,
      sessionJson: 'session-a',
    );
    db = makeTestDatabase();
    await DomainOptInStore(db).write(DomainOptIns(const {DomainScope.health}));
    api = _Api();
    now = DateTime(2026, 9, 12, 7);
    var stamp = 0;
    container = ProviderContainer(
      overrides: [
        activeUserIdProvider.overrideWith((ref) => ref.watch(_owner)),
        currentUserIdProvider.overrideWith((ref) {
          final owner = ref.watch(_owner);
          return () async => owner;
        }),
        appDatabaseProvider.overrideWith((ref) async => db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        outboxStoreProvider.overrideWith((ref) async => InMemoryOutboxStore()),
        mutationStamperProvider.overrideWith(
          (ref) async => MutationStamper(
            currentUserId: () async => ref.read(_owner),
            deviceId: () async => 'test-device',
            stampHlc: () async => Hlc(
              wallMillis: 1700000000000 + stamp++,
              counter: 0,
              nodeId: 'test-device',
            ),
          ),
        ),
        garminTokenStoreProvider.overrideWithValue(tokens),
        garminForegroundAvailableProvider.overrideWithValue(true),
        garminClockProvider.overrideWithValue(() => now),
        garminBridgeProvider.overrideWithValue(
          GarminBridge(
            nativeApi: api,
            initRuntime: ({String? libraryPath}) async {},
          ),
        ),
      ],
    );
    await container.read(auth.domainOptInsProvider.future);
    await container
        .read(garminSyncControllerProvider.notifier)
        .restoreSession();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<HealthRefreshSourceResult> refresh({
    bool automatic = false,
    int days = 3,
  }) => container
      .read(garminSyncControllerProvider.notifier)
      .syncNow(
        automatic: automatic,
        window: Duration(days: days),
      );

  test('same-day steps update and late sleep are imported without duplicating unchanged rows', () async {
    expect((await refresh()).imported, 1);
    api.steps = 8000;
    api.sleep = true;
    final second = await refresh();
    expect(second.imported, 2);
    final third = await refresh();
    expect(third.imported, 0);
    expect(third.unchanged, 2);
    final repo = await container.read(healthMetricRepositoryProvider.future);
    expect((await repo.findById('garmin:steps:2026-09-12'))!.value, 8000);
    expect(await repo.findById('garmin:sleep:test'), isNotNull);
    expect(api.ranges, everyElement(('2026-09-10', '2026-09-12')));
  });

  test(
    'automatic refresh observes freshness while manual refresh bypasses it',
    () async {
      await refresh();
      expect(
        (await refresh(automatic: true)).outcome,
        HealthRefreshOutcome.skipped,
      );
      expect(api.ranges.length, 1);
      await refresh();
      expect(api.ranges.length, 2);
      now = now.add(const Duration(minutes: 31));
      await refresh(automatic: true);
      expect(api.ranges.length, 3);
    },
  );

  test('concurrent manual and automatic calls share an import', () async {
    api.gate = Completer<void>();
    final first = refresh();
    await api.started.future;
    final second = refresh(automatic: true);
    api.gate!.complete();
    final results = await Future.wait([first, second]);
    expect(api.ranges.length, 1);
    expect(results.map((r) => r.imported), [1, 1]);
  });

  test(
    'cancel completes every waiter and never imports the cancelled snapshot',
    () async {
      api.gate = Completer<void>();
      final first = refresh();
      await api.started.future;
      final second = refresh();
      await container.read(garminSyncControllerProvider.notifier).cancelSync();
      expect((await first).errorCode, 'cancelled');
      expect((await second).errorCode, 'cancelled');
      final repo = await container.read(healthMetricRepositoryProvider.future);
      expect(await repo.findById('garmin:steps:2026-09-12'), isNull);
      expect(
        GarminSyncStatusStore(prefs).checkedDays('owner-a', 'china'),
        isEmpty,
      );
      expect(
        (await refresh(automatic: true)).outcome,
        HealthRefreshOutcome.skipped,
      );
      api.gate = null;
      expect((await refresh()).imported, 1);
    },
  );

  test(
    'partial failures retain data, diagnostics and the last complete success',
    () async {
      await refresh();
      final lastSuccess = GarminSyncStatusStore(prefs)
          .read('owner-a', region: 'china')!
          .lastSuccessAt;
      now = now.add(const Duration(hours: 1));
      api.steps = 9000;
      api.issue = 'endpoint_failed';
      final result = await refresh();
      expect(result.outcome, HealthRefreshOutcome.partial);
      expect(result.imported, 1);
      final state =
          container.read(garminSyncControllerProvider) as GarminConnected;
      expect(state.partial, isTrue);
      expect(state.lastErrorCode, 'endpoint_failed');
      expect(
        GarminSyncStatusStore(prefs).checkedDays('owner-a', 'china'),
        isEmpty,
      );
      final saved = GarminSyncStatusStore(prefs)
          .read('owner-a', region: 'china')!;
      expect(saved.lastSuccessAt, lastSuccess);
      expect(saved.nextRetryAt, now.toUtc().add(const Duration(minutes: 5)));
      expect(
        (await refresh(automatic: true)).outcome,
        HealthRefreshOutcome.skipped,
      );
      now = now.add(const Duration(minutes: 6));
      api.issue = null;
      expect(
        (await refresh(automatic: true)).outcome,
        HealthRefreshOutcome.synced,
      );
    },
  );

  test(
    'cancellation before native startup is re-sent after its acknowledgement',
    () async {
      api.startGate = Completer<void>();
      final inFlight = refresh();
      await api.started.future;
      final cancellation = container
          .read(garminSyncControllerProvider.notifier)
          .cancelSync();
      await Future<void>.delayed(Duration.zero);
      expect(api.cancelCalls, 1);
      api.startGate!.complete();
      await cancellation;
      expect((await inFlight).errorCode, 'cancelled');
      expect(api.cancelCalls, 2);
      final repo = await container.read(healthMetricRepositoryProvider.future);
      expect(await repo.findById('garmin:steps:2026-09-12'), isNull);
      api.startGate = null;
      expect((await refresh()).imported, 1);
    },
  );

  test('rate-limit cooldown also applies to manual refresh', () async {
    api.issue = 'rate_limited';
    await refresh();
    expect((await refresh()).outcome, HealthRefreshOutcome.skipped);
    expect(api.ranges.length, 1);
    now = now.add(const Duration(minutes: 31));
    api.issue = null;
    expect((await refresh()).outcome, HealthRefreshOutcome.synced);
  });

  test('unsupported optional endpoints use normal cadence and retain daily checkpoints', () async {
    api.issue = 'endpoint_unavailable';
    api.issueEndpoint = 'training_status';
    await refresh();
    final saved = GarminSyncStatusStore(prefs)
        .read('owner-a', region: 'china')!;
    expect(saved.partial, isTrue);
    expect(saved.failureCount, 0);
    expect(saved.nextRetryAt, now.toUtc().add(const Duration(minutes: 30)));
    expect(
      GarminSyncStatusStore(prefs).checkedDays('owner-a', 'china').length,
      3,
    );
    now = now.add(const Duration(minutes: 6));
    expect(
      (await refresh(automatic: true)).outcome,
      HealthRefreshOutcome.skipped,
    );
    expect(api.ranges.length, 1);
  });

  test(
    'foreground startup uses the shared controller and respects freshness',
    () async {
      final driver = container.read(garminForegroundRefreshProvider)!;
      addTearDown(driver.stop);
      await Future<void>.delayed(Duration.zero);
      await driver.check();
      expect(api.ranges.first, ('2026-09-10', '2026-09-12'));
      expect(api.ranges.length, 5);
      await driver.check();
      expect(api.ranges.length, 5);
    },
  );

  test('empty history is checkpointed; recent days still refresh and history expires', () async {
    api.empty = true;
    await refresh(days: 30);
    expect(api.ranges.length, 5);
    expect(api.ranges.first, ('2026-09-10', '2026-09-12'));
    expect(api.ranges.last, ('2026-08-14', '2026-08-19'));
    expect(
      GarminSyncStatusStore(prefs).checkedDays('owner-a', 'china').length,
      30,
    );
    await refresh(days: 30);
    expect(api.ranges.length, 6);
    now = now.add(const Duration(days: 8));
    await refresh(days: 30);
    expect(api.ranges.length, 11);
  });

  test(
    'unexpectedly closed stream is a failure, not a successful check',
    () async {
      api.noTerminal = true;
      expect((await refresh()).outcome, HealthRefreshOutcome.failed);
      expect(
        GarminSyncStatusStore(prefs).checkedDays('owner-a', 'china'),
        isEmpty,
      );
      expect(
        GarminSyncStatusStore(prefs)
            .read('owner-a', region: 'china')!
            .lastCheckedAt,
        isNull,
      );
    },
  );

  test(
    'saved-credential recovery preserves MFA and resumes after verification',
    () async {
      await tokens.saveCredentials(
        ownerUserId: 'owner-a',
        credentials: const GarminSavedCredentials(
          email: 'test@example.invalid',
          password: 'test-password',
          region: GarminRegion.china,
        ),
      );
      api.expired = true;
      api.requireMfa = true;
      final result = await refresh();
      expect(result.errorCode, 'mfa_required');
      expect(
        container.read(garminSyncControllerProvider),
        isA<GarminPendingMfa>(),
      );
      await container
          .read(garminSyncControllerProvider.notifier)
          .submitMfa('123456');
      expect(
        container.read(garminSyncControllerProvider),
        isA<GarminConnected>(),
      );
      expect((await refresh()).imported, 1);
    },
  );

  test(
    'owner change discards old results and serializes native initialization',
    () async {
      api.gate = Completer<void>();
      final old = refresh();
      await api.started.future;
      await tokens.saveSession(
        ownerUserId: 'owner-b',
        region: GarminRegion.china,
        sessionJson: 'session-b',
      );
      container.read(_owner.notifier).state = 'owner-b';
      await container.pump();
      await container
          .read(garminSyncControllerProvider.notifier)
          .restoreSession();
      await old;
      final repo = await container.read(healthMetricRepositoryProvider.future);
      expect(await repo.findById('garmin:steps:2026-09-12'), isNull);
      expect(api.initializedSessions.last, 'session-b');
      expect(api.overlapped, isFalse);
      expect(
        GarminSyncStatusStore(prefs).read('owner-b', region: 'china'),
        isNull,
      );
    },
  );

  test(
    'disconnect retains imported data but clears session, status and history',
    () async {
      await refresh();
      await container.read(garminSyncControllerProvider.notifier).disconnect();
      expect(
        container.read(garminSyncControllerProvider),
        isA<GarminInitial>(),
      );
      expect(
        await tokens.loadSession(
          ownerUserId: 'owner-a',
          region: GarminRegion.china,
        ),
        isNull,
      );
      expect(
        GarminSyncStatusStore(prefs).checkedDays('owner-a', 'china'),
        isEmpty,
      );
      final repo = await container.read(healthMetricRepositoryProvider.future);
      expect(await repo.findById('garmin:steps:2026-09-12'), isNotNull);
      expect(
        (await refresh(automatic: true)).outcome,
        HealthRefreshOutcome.skipped,
      );
    },
  );

  test('disabling Health cancels an active import without committing', () async {
    api.gate = Completer<void>();
    final inFlight = refresh();
    await api.started.future;
    await container
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.health, false);
    await container.pump();
    // Reading flushes the domain-gated controller after the store notification.
    await container.read(auth.domainOptInsProvider.future);
    await container.pump();
    expect(container.read(garminSyncControllerProvider), isA<GarminInitial>());
    await inFlight;
    final repo = await container.read(healthMetricRepositoryProvider.future);
    expect(await repo.findById('garmin:steps:2026-09-12'), isNull);
  });

  test('changing region restores the matching session and does not reuse checkpoints', () async {
    await refresh();
    await tokens.saveSession(
      ownerUserId: 'owner-a',
      region: GarminRegion.global,
      sessionJson: 'global-session',
    );
    await container
        .read(garminRegionProvider.notifier)
        .set(GarminRegion.global);
    await container.pump();
    await container
        .read(garminSyncControllerProvider.notifier)
        .restoreSession();
    expect(api.initializedSessions.last, 'global-session');
    expect(
      GarminSyncStatusStore(prefs).checkedDays('owner-a', 'global'),
      isEmpty,
    );
    final result = await refresh(automatic: true);
    expect(result.outcome, HealthRefreshOutcome.synced);
  });

  test('date planner uses local calendar, exact bounds and batches at most seven days', () {
    final local = DateTime(2026, 9, 12, 7);
    expect(garminCalendarDay(local), DateTime.utc(2026, 9, 12));
    final ranges = planGarminRefresh(
      localNow: local,
      checkedDays: {},
      window: const Duration(days: 30),
    );
    expect(ranges.expand((r) => r.dates).toSet().length, 30);
    expect(ranges.every((r) => r.days <= 7), isTrue);
    expect(
      planGarminRefresh(
        localNow: local,
        checkedDays: {},
        window: Duration.zero,
      ).single.days,
      1,
    );
  });
}

class _Api implements GarminNativeApi {
  final ranges = <(String, String)>[];
  final initializedSessions = <String?>[];
  final started = Completer<void>();
  Completer<void>? startGate;
  Completer<void>? gate;
  int cancelCalls = 0;
  int steps = 1000;
  bool sleep = false;
  bool empty = false;
  bool noTerminal = false;
  bool expired = false;
  bool requireMfa = false;
  bool cancelled = false;
  bool inStream = false;
  bool overlapped = false;
  String? issue;
  String issueEndpoint = 'sleep';

  @override
  Future<Object?> initialize({
    String? storedTokenJson,
    required bool isCn,
  }) async {
    overlapped |= inStream;
    initializedSessions.add(storedTokenJson);
    return storedTokenJson == null
        ? '"Unauthenticated"'
        : '{"Authenticated":null}';
  }

  @override
  Future<Object?> authState() async =>
      expired ? '"Unauthenticated"' : '{"Authenticated":null}';
  @override
  Future<Object?> authenticate({
    required String email,
    required String password,
  }) async =>
      requireMfa ? '{"result":"MfaRequired"}' : '{"result":"Authenticated"}';
  @override
  Future<Object?> submitMfa({required String code}) async {
    expired = false;
    return '{"result":"Authenticated"}';
  }

  @override
  Future<Object?> exportSession() async => 'session-export';
  @override
  Future<void> logout() async {}
  @override
  Future<Object?> syncCursors() async => '{}';
  @override
  Future<Object?> syncRange({required String from, required String to}) async =>
      '[]';
  @override
  Future<void> cancelSync() async {
    cancelCalls++;
    cancelled = true;
    if (gate case final Completer<void> value when !value.isCompleted) {
      value.complete();
    }
  }

  @override
  Stream<rust.GarminSyncProgress> syncRangeWithProgress({
    required String from,
    required String to,
  }) async* {
    inStream = true;
    ranges.add((from, to));
    if (!started.isCompleted) started.complete();
    try {
      await startGate?.future;
      cancelled = false;
      yield const rust.GarminSyncProgress(
        phase: 'starting',
        current: 0,
        total: 3,
        metricsCount: 0,
        errors: [],
      );
      await gate?.future;
      if (cancelled) {
        yield const rust.GarminSyncProgress(
          phase: 'cancelled',
          current: 0,
          total: 3,
          metricsCount: 0,
          errors: [],
        );
        return;
      }
      if (noTerminal) return;
      final snapshot = empty
          ? <String, Object?>{}
          : <String, Object?>{
              'steps': [
                {
                  'id': 'garmin:steps:2026-09-12',
                  'date': '2026-09-12',
                  'value': steps,
                  'source_device': 'garmin',
                },
              ],
              if (sleep)
                'sleep_sessions': [
                  {
                    'id': 'garmin:sleep:test',
                    'started_at': '2026-09-11T23:00:00Z',
                    'duration_seconds': 27000,
                    'source_device': 'garmin',
                  },
                ],
            };
      yield rust.GarminSyncProgress(
        phase: 'done',
        current: 3,
        total: 3,
        metricsCount: empty
            ? 0
            : sleep
            ? 2
            : 1,
        errors: [
          if (issue != null)
            jsonEncode({
              'source': 'healthos.garmin',
              'code': issue,
              'severity': 'warning',
              'endpoint': issueEndpoint,
              'message': 'Test failure',
              'retryable': true,
              'action': issue == 'endpoint_unavailable' ? 'none' : 'retry',
            }),
        ],
        snapshotJson: jsonEncode(snapshot),
      );
    } finally {
      inStream = false;
    }
  }
}
