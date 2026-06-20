import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/security/flutter_secure_key_store.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'delegates read/write/contains/delete to FlutterSecureStorage',
    () async {
      final store = FlutterSecureKeyStore();

      expect(await store.contains('refresh-token'), isFalse);
      expect(await store.read('refresh-token'), isNull);

      await store.write('refresh-token', 'token-v1');

      expect(await store.contains('refresh-token'), isTrue);
      expect(await store.read('refresh-token'), 'token-v1');

      await store.write('refresh-token', 'token-v2');
      expect(await store.read('refresh-token'), 'token-v2');

      await store.delete('refresh-token');

      expect(await store.contains('refresh-token'), isFalse);
      expect(await store.read('refresh-token'), isNull);
    },
  );

  test('reads values seeded in the secure-storage test platform', () async {
    FlutterSecureStorage.setMockInitialValues({'db-key': 'seeded-secret'});
    final store = FlutterSecureKeyStore();

    expect(await store.contains('db-key'), isTrue);
    expect(await store.read('db-key'), 'seeded-secret');
  });
}
