/// Persistent token store for Garmin Connect sessions.
///
/// Backed by `FlutterSecureStorage` so credentials survive app restarts.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Key used in secure storage for the Garmin session JSON.
const _kGarminSessionKey = 'garmin_session_json';

/// Persists the Garmin session JSON across app launches.
class GarminTokenStore {
  GarminTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  /// Save the session JSON exported from the Rust side.
  Future<void> save(String sessionJson) =>
      _storage.write(key: _kGarminSessionKey, value: sessionJson);

  /// Load the stored session JSON, or `null` if not persisted.
  Future<String?> load() => _storage.read(key: _kGarminSessionKey);

  /// Clear stored credentials (used on disconnect).
  Future<void> clear() => _storage.delete(key: _kGarminSessionKey);
}
