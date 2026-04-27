import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:naviwealth/core/security/db_key_provider.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';

class _FixedRandom implements Random {
  _FixedRandom(this.byte);
  final int byte;

  @override
  int nextInt(int max) => byte;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

void main() {
  group('DbKeyProvider', () {
    test('getOrCreate generates a 64-char hex key on first call', () async {
      final store = InMemoryKeyStore();
      final provider = DbKeyProvider(store);

      final key = await provider.getOrCreate();

      expect(key, hasLength(64));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(key), isTrue);
      expect(await store.read(DbKeyProvider.storageKey), key);
    });

    test('getOrCreate returns the persisted key on subsequent calls', () async {
      final store = InMemoryKeyStore();
      final provider = DbKeyProvider(store);

      final first = await provider.getOrCreate();
      final second = await provider.getOrCreate();

      expect(second, first);
    });

    test('uses the supplied Random source', () async {
      final provider = DbKeyProvider(
        InMemoryKeyStore(),
        random: _FixedRandom(0xab),
      );
      final key = await provider.getOrCreate();
      expect(key, 'ab' * 32);
    });

    test('overwrite rejects malformed keys', () async {
      final provider = DbKeyProvider(InMemoryKeyStore());

      expect(
        () => provider.overwrite('too-short'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => provider.overwrite('z' * 64),
        throwsA(isA<FormatException>()),
      );
    });

    test('erase clears the persisted key', () async {
      final store = InMemoryKeyStore();
      final provider = DbKeyProvider(store);

      await provider.getOrCreate();
      await provider.erase();

      expect(await store.contains(DbKeyProvider.storageKey), isFalse);
    });
  });
}
