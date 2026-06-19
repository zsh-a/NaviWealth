import 'auth_session.dart';

/// One row of `GET /auth/devices`.
class AuthDevice {
  const AuthDevice({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastSeenAt,
  });

  factory AuthDevice.fromJson(Map<String, Object?> json) => AuthDevice(
    id: json['id'] as String,
    name: json['name'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    lastSeenAt: DateTime.parse(json['last_seen_at'] as String).toUtc(),
  );

  final String id;

  /// Optional human label set at login time. May be null for older sessions.
  final String? name;
  final DateTime createdAt;
  final DateTime lastSeenAt;
}

class DevicesResponse {
  const DevicesResponse({required this.devices, required this.currentDeviceId});
  final List<AuthDevice> devices;
  final String currentDeviceId;
}

/// Refreshed access token returned by `POST /auth/refresh`.
///
/// The backend rotates the JWT and the device-row's `jti` together but keeps
/// `user_id` / `device_id` stable, so callers extend an existing
/// [AuthSession] via [AuthSession.withRotatedToken].
class RefreshedToken {
  const RefreshedToken({required this.accessToken, required this.expiresAt});
  final String accessToken;
  final DateTime expiresAt;
}

/// Wire-protocol contract with the backend.
///
/// All methods either return a successful response or throw an
/// [AuthException]. Concrete implementations live in
/// `dio_auth_api_client.dart`; tests double the abstract type.
abstract class AuthApiClient {
  /// `POST /auth/login` — body `{email, password, device_name?, device_id?}`.
  ///
  /// Backend deliberately burns the argon2 cost on email misses, so a
  /// `401` here always maps to [AuthErrorKind.invalidCredentials].
  Future<AuthSession> login({
    required String email,
    required String password,
    required List<String> domains,
    String? deviceName,
    String? deviceId,
  });

  /// `POST /auth/register` — creates the first backend account and returns
  /// the same session envelope as login. The backend rejects later attempts
  /// once a user row already exists.
  Future<AuthSession> register({
    required String email,
    required String password,
    required List<String> domains,
    String? deviceName,
    String? deviceId,
  });

  /// `POST /auth/refresh` (Bearer). Rotates the JWT for the current device.
  Future<RefreshedToken> refresh(
    AuthSession current, {
    required List<String> domains,
  });

  /// `GET /auth/devices` (Bearer).
  Future<DevicesResponse> listDevices(AuthSession current);

  /// `POST /auth/logout/:device_id` (Bearer).
  ///
  /// Revoking the *current* device's row will cause subsequent requests with
  /// the current token to fail 401; callers should clear local state when
  /// `deviceId == current.deviceId`.
  Future<void> logoutDevice(AuthSession current, String deviceId);
}
