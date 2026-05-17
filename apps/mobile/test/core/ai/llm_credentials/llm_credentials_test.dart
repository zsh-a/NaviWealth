import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credential_store.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/core/security/secure_key_store.dart';
import 'package:naviwealth/data/db/providers.dart';

LlmProfile _p(
  String id, {
  String name = '',
  String key = 'k',
  String? baseUrl,
  String? model,
}) => LlmProfile(
  id: id,
  name: name,
  provider: LlmProvider.anthropic,
  apiKey: key,
  baseUrl: baseUrl,
  model: model,
);

ProviderContainer _container(
  SecureKeyStore store, {
  bool platformSupported = true,
}) {
  return ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(store),
      deviceLlmPlatformSupportedProvider.overrideWithValue(platformSupported),
    ],
  );
}

void main() {
  group('LlmCredentials model', () {
    test('v2 encode/decode roundtrip preserves profiles + active', () {
      final c = LlmCredentials(
        profiles: [
          _p('a', name: 'Official', baseUrl: 'https://api.anthropic.com'),
          _p('b', name: 'Gateway', model: 'claude-opus-4-7'),
        ],
        activeId: 'b',
      );
      final back = LlmCredentials.decode(c.encode());
      expect(back, c);
      expect(back.active!.id, 'b');
      expect(back.active!.model, 'claude-opus-4-7');
    });

    test('base_url / model omitted from wire when null', () {
      final c = LlmCredentials(profiles: [_p('a')], activeId: 'a');
      expect(c.encode().contains('base_url'), isFalse);
      expect(c.encode().contains('"model"'), isFalse);
    });

    test('isUsable iff the active profile has a key', () {
      expect(const LlmCredentials().isUsable, isFalse);
      expect(
        LlmCredentials(profiles: [_p('a', key: '  ')], activeId: 'a').isUsable,
        isFalse,
      );
      expect(
        LlmCredentials(profiles: [_p('a')], activeId: 'a').isUsable,
        isTrue,
      );
      // Dangling activeId → not usable.
      expect(
        LlmCredentials(profiles: [_p('a')], activeId: 'zzz').isUsable,
        isFalse,
      );
    });

    test('legacy v1 single-key blob migrates to one active profile', () {
      final c = LlmCredentials.decode(
        '{"provider":"anthropic","api_key":"sk","base_url":"https://gw",'
        '"enabled":false}',
      );
      expect(c.profiles, hasLength(1));
      expect(c.active!.apiKey, 'sk');
      expect(c.active!.baseUrl, 'https://gw');
      // Activated regardless of the dropped legacy `enabled` flag.
      expect(c.isUsable, isTrue);
    });

    test('decode rejects malformed input; unknown provider soft-falls', () {
      expect(
        () => LlmCredentials.decode('not json'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => LlmCredentials.decode('[]'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => LlmCredentials.decode('{"enabled":true}'),
        throwsA(isA<FormatException>()),
      );
      final c = LlmCredentials.decode('{"api_key":"k","provider":"grok"}');
      expect(c.active!.provider, LlmProvider.anthropic);
    });

    test('container ops: upsert / activate / remove', () {
      var c = const LlmCredentials();
      c = c.upsert(_p('a', name: 'A'));
      expect(c.activeId, 'a'); // first profile auto-activates
      c = c.upsert(_p('b', name: 'B'));
      expect(c.activeId, 'a'); // adding another does not steal active
      c = c.upsert(_p('a', name: 'A2')); // editing keeps active
      expect(c.activeId, 'a');
      expect(c.profiles.firstWhere((p) => p.id == 'a').name, 'A2');
      c = c.withActive('b');
      expect(c.active!.id, 'b');
      c = c.remove('b'); // removing active rolls to first remaining
      expect(c.activeId, 'a');
      c = c.remove('a');
      expect(c.isEmpty, isTrue);
      expect(c.activeId, isNull);
    });
  });

  group('LlmCredentialStore', () {
    test('write/read roundtrips; clear wipes', () async {
      final store = LlmCredentialStore(InMemoryKeyStore());
      final c = LlmCredentials(profiles: [_p('a')], activeId: 'a');
      await store.write(c);
      expect(await store.read(), c);
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('corrupt entry is dropped and read falls back to null', () async {
      final raw = InMemoryKeyStore({LlmCredentialStore.storageKey: '{bad'});
      final store = LlmCredentialStore(raw);
      expect(await store.read(), isNull);
      expect(await raw.contains(LlmCredentialStore.storageKey), isFalse);
    });
  });

  group('LlmCredentialsNotifier', () {
    test('upsert persists; first profile becomes active', () async {
      final container = _container(InMemoryKeyStore());
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      final n = container.read(llmCredentialsProvider.notifier);

      await n.upsertProfile(_p('a', key: 'k1'));
      final v = container.read(llmCredentialsProvider).asData?.value;
      expect(v?.active?.apiKey, 'k1');
      expect(v?.isUsable, isTrue);
    });

    test('setActive switches the active profile', () async {
      final container = _container(InMemoryKeyStore());
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      final n = container.read(llmCredentialsProvider.notifier);
      await n.upsertProfile(_p('a', key: 'k1'));
      await n.upsertProfile(_p('b', key: 'k2'));
      await n.setActive('b');
      expect(
        container.read(llmCredentialsProvider).asData?.value?.active?.id,
        'b',
      );
    });

    test('removeProfile, then clearAll wipes to null', () async {
      final container = _container(InMemoryKeyStore());
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      final n = container.read(llmCredentialsProvider.notifier);
      await n.upsertProfile(_p('a', key: 'k1'));
      await n.upsertProfile(_p('b', key: 'k2'));
      await n.removeProfile('a');
      expect(
        container.read(llmCredentialsProvider).asData?.value?.profiles,
        hasLength(1),
      );
      await n.clearAll();
      expect(container.read(llmCredentialsProvider).asData?.value, isNull);
    });

    test('keyless upsert is ignored', () async {
      final container = _container(InMemoryKeyStore());
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      await container
          .read(llmCredentialsProvider.notifier)
          .upsertProfile(_p('a', key: '   '));
      expect(container.read(llmCredentialsProvider).asData?.value, isNull);
    });
  });

  group('deviceLlmAvailableProvider', () {
    test('false when platform unsupported even with a usable profile', () async {
      final c = LlmCredentials(profiles: [_p('a')], activeId: 'a');
      final container = _container(
        InMemoryKeyStore({LlmCredentialStore.storageKey: c.encode()}),
        platformSupported: false,
      );
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      expect(container.read(deviceLlmAvailableProvider), isFalse);
    });

    test('false when no profiles configured', () async {
      final container = _container(InMemoryKeyStore());
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      expect(container.read(deviceLlmAvailableProvider), isFalse);
    });

    test('true when supported and the active profile has a key', () async {
      final c = LlmCredentials(profiles: [_p('a')], activeId: 'a');
      final container = _container(
        InMemoryKeyStore({LlmCredentialStore.storageKey: c.encode()}),
      );
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      expect(container.read(deviceLlmAvailableProvider), isTrue);
    });
  });

  test('platform gate = all native (incl. desktop); only web excluded', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(deviceLlmPlatformSupportedProvider), !kIsWeb);
    expect(container.read(deviceLlmPlatformSupportedProvider), isTrue);
  });
}
