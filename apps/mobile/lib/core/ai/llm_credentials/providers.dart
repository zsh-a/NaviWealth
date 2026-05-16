/// Riverpod wiring for the on-device LLM credentials (§4.6).
///
/// Layering follows the house style: the store is a plain [Provider]
/// over the shared [secureKeyStoreProvider]; the mutable async state
/// is a [ConventionalAsyncNotifier]; everything synchronous & derived
/// (platform support, "is the device runtime usable") is a plain
/// [Provider] so the W-D3 [RuntimeRegistry] can read it cheaply.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/providers.dart' show secureKeyStoreProvider;
import '../../async/async_notifier_convention.dart';
import 'llm_credential_store.dart';
import 'llm_credentials.dart';

/// Secure-storage-backed credential store. Tests override
/// [secureKeyStoreProvider] with `InMemoryKeyStore` rather than this
/// provider (rule 5: override the data layer, not the notifier).
final llmCredentialStoreProvider = Provider<LlmCredentialStore>((ref) {
  return LlmCredentialStore(ref.watch(secureKeyStoreProvider));
});

/// Whether this build can host the device LLM runtime at all.
///
/// §4.6.1 decision 5 (amended): **all native platforms** — iOS,
/// Android, **and desktop (macOS / Windows / Linux)**. The original
/// rationale (system-level secure storage for the key + native HTTP so
/// no browser CORS / JS key exposure) holds identically on desktop:
/// `flutter_secure_storage` ^10 maps to the macOS Keychain, the Windows
/// credential store, and Linux libsecret. Only **web** stays on the
/// cloud relay (IndexedDB-only key + browser-direct CORS).
final deviceLlmPlatformSupportedProvider = Provider<bool>((ref) {
  return !kIsWeb;
});

/// The user's stored credentials (or `null` if none / opted out /
/// corrupt). `build()` reads the Keychain once; `save` / `clear` /
/// `setEnabled` mutate through [AsyncValue.guard] per the convention.
final llmCredentialsProvider =
    AsyncNotifierProvider<LlmCredentialsNotifier, LlmCredentials?>(
  LlmCredentialsNotifier.new,
);

class LlmCredentialsNotifier extends ConventionalAsyncNotifier<LlmCredentials?> {
  @override
  Future<LlmCredentials?> fetch() =>
      ref.read(llmCredentialStoreProvider).read();

  /// Persist a full credential set (Settings "Save"). Writing an empty
  /// key is treated as a clear so the UI has one obvious path.
  Future<void> save(LlmCredentials credentials) async {
    state = await AsyncValue.guard(() async {
      final store = ref.read(llmCredentialStoreProvider);
      if (!credentials.hasKey) {
        await store.clear();
        return null;
      }
      await store.write(credentials);
      return credentials;
    });
  }

  /// Flip only the opt-in switch, keeping the stored key. No key ⇒
  /// no-op (nothing to enable).
  Future<void> setEnabled(bool enabled) async {
    final current = state.asData?.value;
    if (current == null || !current.hasKey) return;
    await save(current.copyWith(enabled: enabled));
  }

  /// Wipe the key from the Keychain entirely.
  Future<void> clear() async {
    state = await AsyncValue.guard(() async {
      await ref.read(llmCredentialStoreProvider).clear();
      return null;
    });
  }
}

/// The single boolean W-D3's `RuntimeRegistry.pickFor` consumes:
/// native platform **and** opted-in credentials with a non-empty key.
/// Resolves to `false` while credentials are still loading or errored
/// (fail closed → cloud relay).
final deviceLlmAvailableProvider = Provider<bool>((ref) {
  if (!ref.watch(deviceLlmPlatformSupportedProvider)) return false;
  final creds = ref.watch(llmCredentialsProvider).asData?.value;
  return creds?.isUsable ?? false;
});
