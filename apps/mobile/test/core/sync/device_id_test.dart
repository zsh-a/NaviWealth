import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/core/sync/device_id.dart';

void main() {
  group('DeviceIdProvider', () {
    test('generates a UUID and persists it on first call', () async {
      final store = InMemoryKeyStore();
      final p = DeviceIdProvider(store: store);
      final id1 = await p.getOrCreate();
      expect(id1.length, 36); // UUID canonical form
      // Persisted to the store under the documented key.
      expect(await store.read('sync.device_id'), id1);
    });

    test('returns the same id across calls and across instances', () async {
      final store = InMemoryKeyStore();
      final id1 = await DeviceIdProvider(store: store).getOrCreate();
      final id2 = await DeviceIdProvider(store: store).getOrCreate();
      expect(id1, id2);
    });
  });
}
