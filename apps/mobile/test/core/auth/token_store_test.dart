import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/auth/device_identity_store.dart';
import 'package:naviwealth/core/auth/token_store.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';

AuthSession _session({DateTime? expiresAt}) => AuthSession(
  accessToken: 'eyJhbGciOiJIUzI1NiJ9.payload.sig',
  expiresAt: expiresAt ?? DateTime.utc(2026, 6, 1),
  userId: 'u-1',
  deviceId: 'd-1',
);

void main() {
  group('TokenStore', () {
    test('read returns null when nothing is persisted', () async {
      final store = TokenStore(InMemoryKeyStore());
      expect(await store.read(), isNull);
    });

    test('write then read round-trips the session', () async {
      final keyStore = InMemoryKeyStore();
      final store = TokenStore(keyStore);
      await store.write(_session());

      final loaded = await store.read();
      expect(loaded, isNotNull);
      expect(loaded!.accessToken, _session().accessToken);
      expect(loaded.userId, 'u-1');
      expect(loaded.deviceId, 'd-1');
      expect(loaded.expiresAt, DateTime.utc(2026, 6, 1));
    });

    test('clear removes the persisted session', () async {
      final keyStore = InMemoryKeyStore();
      final store = TokenStore(keyStore);
      await store.write(_session());
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('corrupt entry is dropped instead of crashing', () async {
      final keyStore = InMemoryKeyStore({
        TokenStore.storageKey: 'not even close to JSON',
      });
      final store = TokenStore(keyStore);
      expect(await store.read(), isNull);
      // Corrupt entry should have been wiped so the next launch is clean.
      expect(await keyStore.contains(TokenStore.storageKey), isFalse);
    });
  });

  group('DeviceIdentityStore', () {
    test('creates and persists a stable install device id', () async {
      final keyStore = InMemoryKeyStore();
      final store = DeviceIdentityStore(keyStore);

      final first = await store.getOrCreate();
      final second = await store.getOrCreate();

      expect(first, isNotEmpty);
      expect(second, first);
      expect(await keyStore.read(DeviceIdentityStore.storageKey), first);
    });

    test('reuses an existing install device id', () async {
      final keyStore = InMemoryKeyStore({
        DeviceIdentityStore.storageKey: '0711901b-f1a4-4090-b490-117a23d24652',
      });
      final store = DeviceIdentityStore(keyStore);

      expect(await store.getOrCreate(), '0711901b-f1a4-4090-b490-117a23d24652');
    });

    test('remember replaces the stored server-approved device id', () async {
      final keyStore = InMemoryKeyStore({
        DeviceIdentityStore.storageKey: '0711901b-f1a4-4090-b490-117a23d24652',
      });
      final store = DeviceIdentityStore(keyStore);

      await store.remember('98fa5788-438f-4fa7-b2b8-80cc76d3cd45');

      expect(await store.getOrCreate(), '98fa5788-438f-4fa7-b2b8-80cc76d3cd45');
    });
  });

  group('AuthSession.isExpired', () {
    test('returns true past expiresAt', () {
      final session = _session(expiresAt: DateTime.utc(2026, 1, 1));
      expect(session.isExpired(now: DateTime.utc(2026, 2, 1)), isTrue);
    });

    test('returns false before expiresAt', () {
      final session = _session(expiresAt: DateTime.utc(2026, 6, 1));
      expect(session.isExpired(now: DateTime.utc(2026, 5, 31)), isFalse);
    });
  });

  group('AuthSession.withRotatedToken', () {
    test('keeps user_id / device_id, swaps token + expiry', () {
      final original = _session();
      final rotated = original.withRotatedToken(
        accessToken: 'new-token',
        expiresAt: DateTime.utc(2026, 12, 31),
      );
      expect(rotated.accessToken, 'new-token');
      expect(rotated.expiresAt, DateTime.utc(2026, 12, 31));
      expect(rotated.userId, original.userId);
      expect(rotated.deviceId, original.deviceId);
    });
  });
}
