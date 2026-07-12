import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../security/secure_key_store.dart';

/// Stable install-level device identity used by auth and sync.
///
/// The backend binds every JWT to a `device_id`, and sync rejects ops whose
/// `device_id` does not match that JWT. Keeping this id stable across logout /
/// login prevents local outbox rows from being stranded behind a new server
/// device id on every login.
class DeviceIdentityStore {
  /// Backward-compatible constructor used by tests and embedders that still
  /// want a [SecureKeyStore] as the canonical store.
  DeviceIdentityStore(
    SecureKeyStore store, {
    Uuid uuid = const Uuid(),
    Duration persistenceTimeout = const Duration(seconds: 2),
    void Function(String errorCode)? onWarning,
  }) : this._(
         primary: _SecureDeviceIdentityPersistence(store),
         uuid: uuid,
         persistenceTimeout: persistenceTimeout,
         onWarning: onWarning,
       );

  /// Production storage: the install id is not a secret, so it lives in the
  /// already-warmed preferences store. The former Keychain value is consulted
  /// once, with a short deadline, to preserve existing installations.
  DeviceIdentityStore.withPreferences({
    required SharedPreferences preferences,
    required SecureKeyStore legacyStore,
    Uuid uuid = const Uuid(),
    Duration legacyReadTimeout = const Duration(milliseconds: 500),
    Duration persistenceTimeout = const Duration(seconds: 2),
    void Function(String errorCode)? onWarning,
  }) : this._(
         primary: _PreferencesDeviceIdentityPersistence(preferences),
         legacyStore: legacyStore,
         uuid: uuid,
         legacyReadTimeout: legacyReadTimeout,
         persistenceTimeout: persistenceTimeout,
         onWarning: onWarning,
       );

  DeviceIdentityStore._({
    required _DeviceIdentityPersistence primary,
    required Uuid uuid,
    required Duration persistenceTimeout,
    Duration legacyReadTimeout = Duration.zero,
    SecureKeyStore? legacyStore,
    void Function(String errorCode)? onWarning,
  }) : _primary = primary,
       _legacyStore = legacyStore,
       _uuid = uuid,
       _legacyReadTimeout = legacyReadTimeout,
       _persistenceTimeout = persistenceTimeout,
       _onWarning = onWarning;

  static const String storageKey = 'naviwealth.install_device_id';

  final _DeviceIdentityPersistence _primary;
  final SecureKeyStore? _legacyStore;
  final Uuid _uuid;
  final Duration _legacyReadTimeout;
  final Duration _persistenceTimeout;
  final void Function(String errorCode)? _onWarning;
  String? _cached;
  Future<String>? _inFlight;

  Future<String> getOrCreate() {
    final cached = _cached;
    if (cached != null) return Future<String>.value(cached);
    final current = _inFlight;
    if (current != null) return current;

    late final Future<String> operation;
    operation = _loadOrCreate().whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
    _inFlight = operation;
    return operation;
  }

  Future<void> remember(String deviceId) async {
    if (deviceId.isEmpty) return;
    _cached = deviceId;
    await _persist(deviceId);
  }

  Future<String> _loadOrCreate() async {
    final primary = await _readPrimary();
    if (primary != null && primary.isNotEmpty) {
      return _cached = primary;
    }

    final legacy = await _readLegacy();
    final id = legacy != null && legacy.isNotEmpty ? legacy : _uuid.v4();
    _cached = id;
    await _persist(id);
    return id;
  }

  Future<String?> _readPrimary() async {
    try {
      return await _primary.read(storageKey).timeout(_persistenceTimeout);
    } on TimeoutException {
      _onWarning?.call('primary_read_timeout');
      return null;
    } catch (_) {
      _onWarning?.call('primary_read_failed');
      return null;
    }
  }

  Future<String?> _readLegacy() async {
    final store = _legacyStore;
    if (store == null || _legacyReadTimeout <= Duration.zero) return null;
    try {
      return await store.read(storageKey).timeout(_legacyReadTimeout);
    } on TimeoutException {
      _onWarning?.call('legacy_read_timeout');
      return null;
    } catch (_) {
      _onWarning?.call('legacy_read_failed');
      return null;
    }
  }

  Future<void> _persist(String deviceId) async {
    try {
      await _primary.write(storageKey, deviceId).timeout(_persistenceTimeout);
    } on TimeoutException {
      _onWarning?.call('primary_write_timeout');
    } catch (_) {
      _onWarning?.call('primary_write_failed');
    }
  }
}

abstract interface class _DeviceIdentityPersistence {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

final class _PreferencesDeviceIdentityPersistence
    implements _DeviceIdentityPersistence {
  const _PreferencesDeviceIdentityPersistence(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<String?> read(String key) async => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}

final class _SecureDeviceIdentityPersistence
    implements _DeviceIdentityPersistence {
  const _SecureDeviceIdentityPersistence(this._store);

  final SecureKeyStore _store;

  @override
  Future<String?> read(String key) => _store.read(key);

  @override
  Future<void> write(String key, String value) => _store.write(key, value);
}
