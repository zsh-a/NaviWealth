import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_region_preference.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_token_store.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('partitions sessions by owner and Garmin region', () async {
    final store = GarminTokenStore();

    await store.saveSession(
      ownerUserId: 'owner-a',
      region: GarminRegion.china,
      sessionJson: 'cn-session',
    );
    await store.saveSession(
      ownerUserId: 'owner-a',
      region: GarminRegion.global,
      sessionJson: 'global-session',
    );

    expect(
      await store.loadSession(
        ownerUserId: 'owner-a',
        region: GarminRegion.china,
      ),
      'cn-session',
    );
    expect(
      await store.loadSession(
        ownerUserId: 'owner-a',
        region: GarminRegion.global,
      ),
      'global-session',
    );
    expect(
      await store.loadSession(
        ownerUserId: 'owner-b',
        region: GarminRegion.china,
      ),
      isNull,
    );
  });

  test(
    'round-trips credentials without exposing email in storage key',
    () async {
      const storage = FlutterSecureStorage();
      final store = GarminTokenStore(storage: storage);
      const credentials = GarminSavedCredentials(
        email: 'person@example.com',
        password: 'secret',
        region: GarminRegion.global,
      );

      await store.saveCredentials(
        ownerUserId: 'owner-a',
        credentials: credentials,
      );

      final restored = await store.loadCredentials(ownerUserId: 'owner-a');
      expect(restored?.email, credentials.email);
      expect(restored?.password, credentials.password);
      expect(restored?.region, credentials.region);
      expect(
        (await storage.readAll()).keys,
        everyElement(isNot(contains(credentials.email))),
      );
    },
  );

  test('clearing a stale session preserves recovery credentials', () async {
    final store = GarminTokenStore();
    const credentials = GarminSavedCredentials(
      email: 'person@example.com',
      password: 'secret',
      region: GarminRegion.china,
    );
    await store.saveSession(
      ownerUserId: 'owner-a',
      region: GarminRegion.china,
      sessionJson: 'session',
    );
    await store.saveCredentials(
      ownerUserId: 'owner-a',
      credentials: credentials,
    );

    await store.clearSession(
      ownerUserId: 'owner-a',
      region: GarminRegion.china,
    );

    expect(
      await store.loadSession(
        ownerUserId: 'owner-a',
        region: GarminRegion.china,
      ),
      isNull,
    );
    expect(
      (await store.loadCredentials(ownerUserId: 'owner-a'))?.password,
      'secret',
    );
  });

  test(
    'clearAll removes sessions and saved credentials for one owner',
    () async {
      final store = GarminTokenStore();
      const credentials = GarminSavedCredentials(
        email: 'person@example.com',
        password: 'secret',
        region: GarminRegion.china,
      );
      for (final region in GarminRegion.values) {
        await store.saveSession(
          ownerUserId: 'owner-a',
          region: region,
          sessionJson: region.wire,
        );
      }
      await store.saveCredentials(
        ownerUserId: 'owner-a',
        credentials: credentials,
      );

      await store.clearAll(ownerUserId: 'owner-a');

      for (final region in GarminRegion.values) {
        expect(
          await store.loadSession(ownerUserId: 'owner-a', region: region),
          isNull,
        );
      }
      expect(await store.loadCredentials(ownerUserId: 'owner-a'), isNull);
    },
  );
}
