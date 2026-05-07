import 'package:uuid/uuid.dart';

import '../security/secure_key_store.dart';

/// Stable install-level device identity used by auth and sync.
///
/// The backend binds every JWT to a `device_id`, and sync rejects ops whose
/// `device_id` does not match that JWT. Keeping this id stable across logout /
/// login prevents local outbox rows from being stranded behind a new server
/// device id on every login.
class DeviceIdentityStore {
  DeviceIdentityStore(this._store, {Uuid uuid = const Uuid()}) : _uuid = uuid;

  static const String storageKey = 'naviwealth.install_device_id';

  final SecureKeyStore _store;
  final Uuid _uuid;

  Future<String> getOrCreate() async {
    final existing = await _store.read(storageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final id = _uuid.v4();
    await _store.write(storageKey, id);
    return id;
  }

  Future<void> remember(String deviceId) async {
    if (deviceId.isEmpty) return;
    await _store.write(storageKey, deviceId);
  }
}
