import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/features/knowledge/data/bcr_github_credentials.dart';

class _ObservedKeyStore extends InMemoryKeyStore {
  final keys = <String>{};
  var reads = 0;
  var writes = 0;
  var deletes = 0;
  var failRead = false;
  var failWrite = false;
  var failDelete = false;

  @override
  Future<String?> read(String key) {
    reads++;
    if (failRead) throw StateError('Platform error: private-token');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) {
    writes++;
    keys.add(key);
    if (failWrite) throw StateError('Platform error: $value');
    return super.write(key, value);
  }

  @override
  Future<void> delete(String key) {
    deletes++;
    if (failDelete) throw StateError('Platform error: private-token');
    return super.delete(key);
  }
}

void main() {
  test(
    'secure documents survive new instances and isolate owner identities',
    () async {
      final keys = _ObservedKeyStore();
      final credentials = BcrGithubCredentials(keys);
      await credentials.write('owner/a', 'same-id', 'first-token');
      await credentials.write('owner.a', 'same-id', 'second-token');
      final reopened = BcrGithubCredentials(keys);
      expect(await reopened.read('owner/a', 'same-id'), 'first-token');
      expect(await reopened.read('owner.a', 'same-id'), 'second-token');
      expect(await reopened.read('owner/a', 'missing'), isNull);
      expect(keys.keys, hasLength(2));
      expect(keys.keys.any((key) => key.contains('owner/a')), isFalse);
      await reopened.clearOwner('owner/a');
      expect(await credentials.read('owner/a', 'same-id'), isNull);
      expect(await credentials.read('owner.a', 'same-id'), 'second-token');
    },
  );

  test(
    'concurrent writes from fresh instances retain every credential',
    () async {
      final keys = InMemoryKeyStore();
      await Future.wait([
        for (var i = 0; i < 12; i++)
          BcrGithubCredentials(keys).write('owner', 'id-$i', 'token-$i'),
      ]);
      for (var i = 0; i < 12; i++) {
        expect(
          await BcrGithubCredentials(keys).read('owner', 'id-$i'),
          'token-$i',
        );
      }
    },
  );

  test(
    'delete and reset serialize with queued writes without losing updates',
    () async {
      final keys = InMemoryKeyStore();
      await BcrGithubCredentials(keys).write('other', 'id', 'other-token');
      await Future.wait([
        BcrGithubCredentials(keys).write('owner', 'first', 'first-token'),
        BcrGithubCredentials(keys).write('owner', 'second', 'second-token'),
        BcrGithubCredentials(keys).delete('owner', 'first'),
        BcrGithubCredentials(keys).write('owner', 'third', 'third-token'),
      ]);
      final credentials = BcrGithubCredentials(keys);
      expect(await credentials.read('owner', 'first'), isNull);
      expect(await credentials.read('owner', 'second'), 'second-token');
      expect(await credentials.read('owner', 'third'), 'third-token');
      await Future.wait([
        BcrGithubCredentials(keys).write('owner', 'before-reset', 'old-token'),
        BcrGithubCredentials(keys).clearOwner('owner'),
        BcrGithubCredentials(keys).write('owner', 'after-reset', 'new-token'),
      ]);
      expect(await credentials.read('owner', 'before-reset'), isNull);
      expect(await credentials.read('owner', 'second'), isNull);
      expect(await credentials.read('owner', 'after-reset'), 'new-token');
      expect(await credentials.read('other', 'id'), 'other-token');
    },
  );

  test(
    'failed writes retain the persisted value and do not poison the queue',
    () async {
      final keys = _ObservedKeyStore();
      final credentials = BcrGithubCredentials(keys);
      await credentials.write('owner', 'id', 'original-token');
      keys.failWrite = true;
      await expectLater(
        credentials.write('owner', 'id', 'replacement-token'),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'safe message',
            allOf(
              isNot(contains('replacement-token')),
              isNot(contains('original-token')),
            ),
          ),
        ),
      );
      expect(await credentials.read('owner', 'id'), 'original-token');
      expect(
        await BcrGithubCredentials(keys).read('owner', 'id'),
        'original-token',
      );
      keys.failWrite = false;
      await credentials.write('owner', 'id', 'repaired-token');
      expect(await credentials.read('owner', 'id'), 'repaired-token');
    },
  );

  test(
    'failed deletion and reset do not claim that a token was removed',
    () async {
      final keys = _ObservedKeyStore();
      final credentials = BcrGithubCredentials(keys);
      await credentials.write('owner', 'id', 'original-token');
      keys.failDelete = true;
      await expectLater(credentials.delete('owner', 'id'), throwsStateError);
      await expectLater(credentials.clearOwner('owner'), throwsStateError);
      expect(await credentials.read('owner', 'id'), 'original-token');
      keys.failDelete = false;
      await credentials.clearOwner('owner');
      expect(await credentials.read('owner', 'id'), isNull);
    },
  );

  test(
    'corrupt documents fail closed and retain their original bytes',
    () async {
      final keys = _ObservedKeyStore();
      final credentials = BcrGithubCredentials(keys);
      await credentials.write('owner', 'id', 'original-token');
      final key = keys.keys.single;
      for (final raw in [
        '{"private-token":',
        jsonEncode({'version': 2, 'tokens': <String, String>{}}),
        jsonEncode({'version': 1, 'tokens': <String>[]}),
        jsonEncode({
          'version': 1,
          'tokens': {'id': 42},
        }),
        jsonEncode({
          'version': 1,
          'tokens': {'id': 'line\nbreak'},
        }),
      ]) {
        await keys.write(key, raw);
        await expectLater(
          credentials.read('owner', 'id'),
          throwsA(
            isA<FormatException>()
                .having((error) => error.source, 'source', isNull)
                .having(
                  (error) => error.toString(),
                  'safe message',
                  isNot(contains('private-token')),
                ),
          ),
        );
        await expectLater(
          credentials.write('owner', 'replacement', 'new-token'),
          throwsFormatException,
        );
        expect(await keys.read(key), raw);
      }
      await credentials.clearOwner('owner');
      expect(await credentials.read('owner', 'id'), isNull);
    },
  );

  test('platform read failures never expose secrets', () async {
    final keys = _ObservedKeyStore()..failRead = true;
    await expectLater(
      BcrGithubCredentials(keys).read('owner', 'id'),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'safe message',
          isNot(contains('private-token')),
        ),
      ),
    );
  });

  test(
    'session-only hosts share memory across instances without storage calls',
    () async {
      final keys = _ObservedKeyStore()
        ..failRead = true
        ..failWrite = true
        ..failDelete = true;
      final credentials = BcrGithubCredentials(keys, persistent: false);
      final resetHost = BcrGithubCredentials(keys, persistent: false);
      await credentials.clearOwner('session-owner');
      await credentials.clearOwner('other-session-owner');
      await Future.wait([
        credentials.write('session-owner', 'first', 'session-token'),
        resetHost.write('session-owner', 'second', 'other-session-token'),
        credentials.write('other-session-owner', 'first', 'isolated-token'),
      ]);
      expect(await resetHost.read('session-owner', 'first'), 'session-token');
      expect(
        await resetHost.read('session-owner', 'second'),
        'other-session-token',
      );
      await resetHost.delete('session-owner', 'first');
      expect(await credentials.read('session-owner', 'first'), isNull);
      await BcrGithubCredentials(
        InMemoryKeyStore(),
        persistent: false,
      ).clearOwner('session-owner');
      expect(await resetHost.read('session-owner', 'second'), isNull);
      expect(
        await resetHost.read('other-session-owner', 'first'),
        'isolated-token',
      );
      await resetHost.clearOwner('other-session-owner');
      expect(keys.reads, 0);
      expect(keys.writes, 0);
      expect(keys.deletes, 0);
    },
  );

  test(
    'session-only tokens are never read from persistent credentials',
    () async {
      final keys = InMemoryKeyStore();
      final persistent = BcrGithubCredentials(keys);
      final session = BcrGithubCredentials(keys, persistent: false);
      await session.clearOwner('mixed-owner');
      await persistent.write('mixed-owner', 'id', 'persistent-token');
      expect(await session.read('mixed-owner', 'id'), isNull);
      await session.write('mixed-owner', 'id', 'session-token');
      expect(await persistent.read('mixed-owner', 'id'), 'persistent-token');
      await session.clearOwner('mixed-owner');
      expect(await persistent.read('mixed-owner', 'id'), 'persistent-token');
    },
  );

  test('invalid identities and multiline tokens never reach storage', () async {
    final keys = _ObservedKeyStore();
    final credentials = BcrGithubCredentials(keys);
    for (final owner in ['', '  ']) {
      await expectLater(credentials.read(owner, 'id'), throwsFormatException);
      await expectLater(
        credentials.write(owner, 'id', 'token'),
        throwsFormatException,
      );
      await expectLater(credentials.delete(owner, 'id'), throwsFormatException);
      await expectLater(credentials.clearOwner(owner), throwsFormatException);
    }
    for (final id in ['', '  ']) {
      await expectLater(credentials.read('owner', id), throwsFormatException);
      await expectLater(
        credentials.write('owner', id, 'token'),
        throwsFormatException,
      );
      await expectLater(credentials.delete('owner', id), throwsFormatException);
    }
    for (final token in ['', '  ', 'a\nb', 'a\rb', 'a\u2028b']) {
      await expectLater(
        credentials.write('owner', 'id', token),
        throwsFormatException,
      );
    }
    expect(keys.reads, 0);
    expect(keys.writes, 0);
    expect(keys.deletes, 0);
    expect(credentials.toString(), 'BcrGithubCredentials(persistent: true)');
  });
}
