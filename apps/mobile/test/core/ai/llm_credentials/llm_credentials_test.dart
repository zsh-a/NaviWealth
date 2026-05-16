import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credential_store.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/core/security/secure_key_store.dart';
import 'package:naviwealth/data/db/providers.dart';

ProviderContainer _container(
  SecureKeyStore store, {
  bool platformSupported = true,
}) {
  return ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(store),
      deviceLlmPlatformSupportedProvider
          .overrideWithValue(platformSupported),
    ],
  );
}

void main() {
  group('LlmCredentials model', () {
    test('encode/decode roundtrip preserves all fields', () {
      const c = LlmCredentials(
        provider: LlmProvider.anthropic,
        apiKey: 'sk-ant-abc',
        baseUrl: 'https://gw.example.com',
        enabled: true,
      );
      expect(LlmCredentials.decode(c.encode()), c);
    });

    test('base_url omitted from wire when null/empty', () {
      const c = LlmCredentials(
        provider: LlmProvider.anthropic,
        apiKey: 'k',
      );
      expect(c.encode().contains('base_url'), isFalse);
      expect(LlmCredentials.decode(c.encode()).baseUrl, isNull);
    });

    test('isUsable requires both opt-in and a non-blank key', () {
      const noKey =
          LlmCredentials(provider: LlmProvider.anthropic, apiKey: '   ', enabled: true);
      const notEnabled =
          LlmCredentials(provider: LlmProvider.anthropic, apiKey: 'k');
      const usable = LlmCredentials(
        provider: LlmProvider.anthropic,
        apiKey: 'k',
        enabled: true,
      );
      expect(noKey.isUsable, isFalse);
      expect(notEnabled.isUsable, isFalse);
      expect(usable.isUsable, isTrue);
    });

    test('decode rejects malformed input and soft-falls unknown provider', () {
      expect(() => LlmCredentials.decode('not json'),
          throwsA(isA<FormatException>()));
      expect(() => LlmCredentials.decode('[]'),
          throwsA(isA<FormatException>()));
      expect(() => LlmCredentials.decode('{"enabled":true}'),
          throwsA(isA<FormatException>()));
      final c = LlmCredentials.decode('{"api_key":"k","provider":"grok"}');
      expect(c.provider, LlmProvider.anthropic);
    });
  });

  group('LlmCredentialStore', () {
    test('read returns null on empty store', () async {
      final store = LlmCredentialStore(InMemoryKeyStore());
      expect(await store.read(), isNull);
    });

    test('write then read roundtrips; clear wipes', () async {
      final store = LlmCredentialStore(InMemoryKeyStore());
      const c = LlmCredentials(
        provider: LlmProvider.anthropic,
        apiKey: 'k',
        enabled: true,
      );
      await store.write(c);
      expect(await store.read(), c);
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('corrupt entry is dropped and read falls back to null', () async {
      final raw = InMemoryKeyStore({
        LlmCredentialStore.storageKey: '{bad',
      });
      final store = LlmCredentialStore(raw);
      expect(await store.read(), isNull);
      expect(await raw.contains(LlmCredentialStore.storageKey), isFalse);
    });
  });

  group('LlmCredentialsNotifier', () {
    test('build reads previously stored credentials', () async {
      const c = LlmCredentials(
        provider: LlmProvider.anthropic,
        apiKey: 'k',
        enabled: true,
      );
      final container = _container(
        InMemoryKeyStore({LlmCredentialStore.storageKey: c.encode()}),
      );
      addTearDown(container.dispose);
      expect(await container.read(llmCredentialsProvider.future), c);
    });

    test('save persists and saving an empty key clears', () async {
      final container = _container(InMemoryKeyStore());
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      final notifier = container.read(llmCredentialsProvider.notifier);

      await notifier.save(const LlmCredentials(
        provider: LlmProvider.anthropic,
        apiKey: 'k',
      ));
      expect(container.read(llmCredentialsProvider).asData?.value?.apiKey, 'k');

      await notifier.save(const LlmCredentials(
        provider: LlmProvider.anthropic,
        apiKey: '',
      ));
      expect(container.read(llmCredentialsProvider).asData?.value, isNull);
    });

    test('setEnabled is a no-op without a stored key', () async {
      final container = _container(InMemoryKeyStore());
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      await container.read(llmCredentialsProvider.notifier).setEnabled(true);
      expect(container.read(llmCredentialsProvider).asData?.value, isNull);
    });

    test('setEnabled flips the opt-in on a stored key', () async {
      final container = _container(InMemoryKeyStore());
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      final notifier = container.read(llmCredentialsProvider.notifier);
      await notifier.save(const LlmCredentials(
        provider: LlmProvider.anthropic,
        apiKey: 'k',
      ));
      await notifier.setEnabled(true);
      expect(
        container.read(llmCredentialsProvider).asData?.value?.enabled,
        isTrue,
      );
    });
  });

  group('deviceLlmAvailableProvider', () {
    test('false when platform unsupported even with usable creds', () async {
      const c = LlmCredentials(
        provider: LlmProvider.anthropic,
        apiKey: 'k',
        enabled: true,
      );
      final container = _container(
        InMemoryKeyStore({LlmCredentialStore.storageKey: c.encode()}),
        platformSupported: false,
      );
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      expect(container.read(deviceLlmAvailableProvider), isFalse);
    });

    test('false when key stored but not opted in', () async {
      const c = LlmCredentials(provider: LlmProvider.anthropic, apiKey: 'k');
      final container = _container(
        InMemoryKeyStore({LlmCredentialStore.storageKey: c.encode()}),
      );
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      expect(container.read(deviceLlmAvailableProvider), isFalse);
    });

    test('true when supported and credentials usable', () async {
      const c = LlmCredentials(
        provider: LlmProvider.anthropic,
        apiKey: 'k',
        enabled: true,
      );
      final container = _container(
        InMemoryKeyStore({LlmCredentialStore.storageKey: c.encode()}),
      );
      addTearDown(container.dispose);
      await container.read(llmCredentialsProvider.future);
      expect(container.read(deviceLlmAvailableProvider), isTrue);
    });
  });

  test('platform gate = all native (incl. desktop); only web excluded', () {
    // §4.6.1 (amended): every native platform is supported; the gate
    // is `!kIsWeb`. The test VM is native ⇒ supported.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(deviceLlmPlatformSupportedProvider), !kIsWeb);
    expect(container.read(deviceLlmPlatformSupportedProvider), isTrue);
  });
}
