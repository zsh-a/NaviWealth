/// Secure, device-local persistence for Garmin sessions and credentials.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'garmin_region_preference.dart';

const _kGarminStoragePrefix = 'lifeos.health.garmin.v2';

/// Garmin credentials that may be used to recover an expired session.
///
/// This value must only be persisted through [GarminTokenStore]. It must never
/// be written to SharedPreferences, Drift, sync payloads, analytics, or logs.
class GarminSavedCredentials {
  const GarminSavedCredentials({
    required this.email,
    required this.password,
    required this.region,
  });

  final String email;
  final String password;
  final GarminRegion region;

  Map<String, Object> toJson() => <String, Object>{
    'email': email,
    'password': password,
    'region': region.wire,
  };

  static GarminSavedCredentials? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final email = value['email'];
    final password = value['password'];
    if (email is! String ||
        email.trim().isEmpty ||
        password is! String ||
        password.isEmpty) {
      return null;
    }
    return GarminSavedCredentials(
      email: email,
      password: password,
      region: GarminRegionX.parse(value['region'] as String?),
    );
  }
}

/// Persists Garmin secrets in the platform Keychain/Keystore.
///
/// Keys are partitioned by NaviWealth owner. Sessions are additionally
/// partitioned by Garmin region because China and Global tokens are not
/// interchangeable.
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

  Future<void> saveSession({
    required String ownerUserId,
    required GarminRegion region,
    required String sessionJson,
  }) =>
      _storage.write(key: _sessionKey(ownerUserId, region), value: sessionJson);

  Future<String?> loadSession({
    required String ownerUserId,
    required GarminRegion region,
  }) => _storage.read(key: _sessionKey(ownerUserId, region));

  Future<void> clearSession({
    required String ownerUserId,
    required GarminRegion region,
  }) => _storage.delete(key: _sessionKey(ownerUserId, region));

  Future<void> saveCredentials({
    required String ownerUserId,
    required GarminSavedCredentials credentials,
  }) => _storage.write(
    key: _credentialsKey(ownerUserId),
    value: jsonEncode(credentials.toJson()),
  );

  Future<GarminSavedCredentials?> loadCredentials({
    required String ownerUserId,
  }) async {
    final raw = await _storage.read(key: _credentialsKey(ownerUserId));
    if (raw == null) return null;
    try {
      return GarminSavedCredentials.fromJson(jsonDecode(raw));
    } on FormatException {
      await clearCredentials(ownerUserId: ownerUserId);
      return null;
    }
  }

  Future<void> clearCredentials({required String ownerUserId}) =>
      _storage.delete(key: _credentialsKey(ownerUserId));

  Future<void> clearAll({required String ownerUserId}) async {
    await Future.wait(<Future<void>>[
      for (final region in GarminRegion.values)
        clearSession(ownerUserId: ownerUserId, region: region),
      clearCredentials(ownerUserId: ownerUserId),
    ]);
  }

  String _sessionKey(String ownerUserId, GarminRegion region) =>
      '$_kGarminStoragePrefix.${_encodedOwner(ownerUserId)}.'
      '${region.wire}.session';

  String _credentialsKey(String ownerUserId) =>
      '$_kGarminStoragePrefix.${_encodedOwner(ownerUserId)}.credentials';

  String _encodedOwner(String ownerUserId) =>
      base64Url.encode(utf8.encode(ownerUserId)).replaceAll('=', '');
}
