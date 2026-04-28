import 'package:uuid/uuid.dart';

import '../security/secure_key_store.dart';

/// Stable per-install device id (`docs/sync-protocol.md` §2). Generated
/// once on first launch, persisted in the platform secure store, and reused
/// for the lifetime of the install.
///
/// Why secure store and not regular preferences:
///  - The id is part of the HLC — clearing it would let two-device-rotated
///    clocks issue colliding HLCs we couldn't disambiguate.
///  - On iOS reinstall the Keychain entry survives, which is what we want:
///    "same device, fresh app" should keep its sync identity.
class DeviceIdProvider {
  DeviceIdProvider({
    required SecureKeyStore store,
    Uuid? uuid,
    String storageKey = 'sync.device_id',
  }) : _store = store,
       _uuid = uuid ?? const Uuid(),
       _key = storageKey;

  final SecureKeyStore _store;
  final Uuid _uuid;
  final String _key;

  String? _cached;

  Future<String> getOrCreate() async {
    if (_cached != null) return _cached!;
    final existing = await _store.read(_key);
    if (existing != null && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }
    final fresh = _uuid.v4();
    await _store.write(_key, fresh);
    _cached = fresh;
    return fresh;
  }

  /// Test-only: forces a specific device id. Real callers should never
  /// rotate the device id mid-session.
  void setForTesting(String value) {
    _cached = value;
  }
}
