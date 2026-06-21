import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/background/background_scheduler.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/health/agents/providers.dart';
import 'package:naviwealth/features/health/data/health_platform_adapter.dart';
import 'package:naviwealth/features/health/data/providers.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-test';
const _deviceId = 'dev-test';

class _FakeHealthPlatformAdapter implements HealthPlatformAdapter {
  _FakeHealthPlatformAdapter({required this.snapshot});

  final HealthPlatformSnapshot snapshot;
  int fetchCalls = 0;
  DateTime? lastFrom;
  DateTime? lastTo;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<HealthPlatformSnapshot> fetchRange({
    required DateTime from,
    required DateTime to,
  }) async {
    fetchCalls++;
    lastFrom = from;
    lastTo = to;
    return snapshot;
  }
}

MutationStamper _fakeStamper({int startMillis = 1_700_000_000_000}) {
  var counter = 0;
  return MutationStamper(
    currentUserId: () async => _userId,
    deviceId: () async => _deviceId,
    stampHlc: () async {
      final hlc = Hlc(
        wallMillis: startMillis + counter,
        counter: 0,
        nodeId: _deviceId,
      );
      counter++;
      return hlc;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'pending platform sync consumes due flag and writes HealthKit data',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kHealthPlatformSyncDueAtKey: DateTime.utc(
          2026,
          6,
          1,
        ).millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      final db = makeTestDatabase();
      addTearDown(db.close);
      await DomainOptInStore(
        db,
      ).write(DomainOptIns(const <DomainScope>{DomainScope.health}));

      final outbox = InMemoryOutboxStore();
      final adapter = _FakeHealthPlatformAdapter(
        snapshot: HealthPlatformSnapshot(
          hrv: <RawDailyValue>[
            RawDailyValue(
              externalId: 'hk:hrv:bg',
              day: DateTime.utc(2026, 6, 1),
              value: 49,
            ),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          outboxStoreProvider.overrideWith((ref) async => outbox),
          sharedPreferencesProvider.overrideWithValue(prefs),
          healthPlatformAdapterProvider.overrideWithValue(adapter),
          mutationStamperProvider.overrideWith((ref) async => _fakeStamper()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(pendingHealthPlatformSyncRunProvider.future);

      expect(prefs.getInt(kHealthPlatformSyncDueAtKey), isNull);
      expect(adapter.fetchCalls, 1);
      expect(
        adapter.lastTo!.difference(adapter.lastFrom!),
        kBackgroundHealthPlatformSyncWindow,
      );

      final repo = await container.read(healthMetricRepositoryProvider.future);
      final row = await repo.findById('hk:hrv:bg');
      expect(row, isNotNull);
      expect(row!.kind, HealthMetricKind.hrvDaily);
      expect(row.value, 49);
      expect(row.sync.ownerUserId, _userId);
      expect(await outbox.depth(), 1);
    },
  );

  test('pending platform sync is gated by Health domain opt-in', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kHealthPlatformSyncDueAtKey: DateTime.utc(
        2026,
        6,
        1,
      ).millisecondsSinceEpoch,
    });
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();
    addTearDown(db.close);
    final outbox = InMemoryOutboxStore();
    final adapter = _FakeHealthPlatformAdapter(
      snapshot: const HealthPlatformSnapshot.empty(),
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        outboxStoreProvider.overrideWith((ref) async => outbox),
        sharedPreferencesProvider.overrideWithValue(prefs),
        healthPlatformAdapterProvider.overrideWithValue(adapter),
        mutationStamperProvider.overrideWith((ref) async => _fakeStamper()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(pendingHealthPlatformSyncRunProvider.future);

    expect(prefs.getInt(kHealthPlatformSyncDueAtKey), isNotNull);
    expect(adapter.fetchCalls, 0);
    expect(await outbox.depth(), 0);
  });
}
