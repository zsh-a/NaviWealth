/// Riverpod wiring for the on-device LLM credentials (§4.6).
///
/// Layering follows the house style: the store is a plain [Provider]
/// over the shared [secureKeyStoreProvider]; the mutable async state
/// is a [ConventionalAsyncNotifier]; everything synchronous & derived
/// (platform support, "is the device runtime usable") is a plain
/// [Provider] so chat routing can fail closed while credentials load.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/providers.dart' show secureKeyStoreProvider;
import '../../async/async_notifier_convention.dart';
import 'llm_connectivity.dart';
import 'llm_credential_store.dart';
import 'llm_credentials.dart';

/// Secure-storage-backed credential store. Tests override
/// [secureKeyStoreProvider] with `InMemoryKeyStore` rather than this
/// provider (rule 5: override the data layer, not the notifier).
final llmCredentialStoreProvider = Provider<LlmCredentialStore>((ref) {
  return LlmCredentialStore(ref.watch(secureKeyStoreProvider));
});

/// One-tap connectivity probe (Wave 46). Stateless; the settings page
/// passes the (possibly unsaved) profile being edited.
final llmConnectivityProbeProvider = Provider<LlmConnectivityProbe>((ref) {
  return LlmConnectivityProbe();
});

/// Whether this build can host the device LLM runtime at all.
///
/// §4.6.1 decision 5 (amended): **all native platforms** — iOS,
/// Android, **and desktop (macOS / Windows / Linux)**. The original
/// rationale (system-level secure storage for the key + native HTTP so
/// no browser CORS / JS key exposure) holds identically on desktop:
/// `flutter_secure_storage` ^10 maps to the macOS Keychain, the Windows
/// credential store, and Linux libsecret. **Web** has no AI runtime
/// because there is no cloud relay fallback and browser-direct keys
/// would be exposed to the page environment.
final deviceLlmPlatformSupportedProvider = Provider<bool>((ref) {
  return !kIsWeb;
});

/// The user's stored credential set (or `null` if none / corrupt).
/// `build()` reads the Keychain once; the mutators persist the whole
/// container through [AsyncValue.guard] per the convention.
final llmCredentialsProvider =
    AsyncNotifierProvider<LlmCredentialsNotifier, LlmCredentials?>(
      LlmCredentialsNotifier.new,
    );

class LlmCredentialsNotifier
    extends ConventionalAsyncNotifier<LlmCredentials?> {
  @override
  Future<LlmCredentials?> fetch() =>
      ref.read(llmCredentialStoreProvider).read();

  LlmCredentials get _current => state.asData?.value ?? const LlmCredentials();

  Future<void> _persist(LlmCredentials next) async {
    state = await AsyncValue.guard(() async {
      final store = ref.read(llmCredentialStoreProvider);
      if (next.isEmpty) {
        await store.clear();
        return null;
      }
      await store.write(next);
      return next;
    });
  }

  /// Add a new profile or replace an existing one by id. A keyless
  /// profile is ignored (the UI blocks this; defensive here too).
  Future<void> upsertProfile(LlmProfile profile) async {
    if (!profile.hasKey) return;
    await _persist(_current.upsert(profile));
  }

  /// Switch which profile the device runtime uses. No-op for an
  /// unknown id.
  Future<void> setActive(String id) async {
    await _persist(_current.withActive(id));
  }

  /// Remove one profile. The active selection rolls to the first
  /// remaining profile (or none).
  Future<void> removeProfile(String id) async {
    await _persist(_current.remove(id));
  }

  /// Wipe every profile from the Keychain.
  Future<void> clearAll() async {
    state = await AsyncValue.guard(() async {
      await ref.read(llmCredentialStoreProvider).clear();
      return null;
    });
  }
}

/// Native platform **and** an active profile carrying a non-empty key.
/// Resolves to `false` while credentials are still loading or errored
/// (fail closed → the turn surfaces `device_unavailable`).
final deviceLlmAvailableProvider = Provider<bool>((ref) {
  if (!ref.watch(deviceLlmPlatformSupportedProvider)) return false;
  final creds = ref.watch(llmCredentialsProvider).asData?.value;
  return creds?.isUsable ?? false;
});
