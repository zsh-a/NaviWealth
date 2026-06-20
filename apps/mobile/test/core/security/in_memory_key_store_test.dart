import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';

void main() {
  test('read and contains reflect seeded values', () async {
    final store = InMemoryKeyStore({'db-key': 'secret'});

    expect(await store.contains('db-key'), isTrue);
    expect(await store.read('db-key'), 'secret');
    expect(await store.contains('missing'), isFalse);
    expect(await store.read('missing'), isNull);
  });

  test('write overwrites existing values and delete removes them', () async {
    final store = InMemoryKeyStore();

    await store.write('refresh-token', 'v1');
    await store.write('refresh-token', 'v2');
    expect(await store.read('refresh-token'), 'v2');

    await store.delete('refresh-token');
    expect(await store.contains('refresh-token'), isFalse);
    expect(await store.read('refresh-token'), isNull);
  });

  test('copies seed map so later caller mutations do not leak in', () async {
    final seed = {'db-key': 'v1'};
    final store = InMemoryKeyStore(seed);

    seed['db-key'] = 'v2';
    seed['refresh-token'] = 'token';

    expect(await store.read('db-key'), 'v1');
    expect(await store.contains('refresh-token'), isFalse);
  });
}
