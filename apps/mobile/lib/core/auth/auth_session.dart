import 'dart:convert';

/// Active access-token session held by the client.
///
/// The backend issues a single long-lived (30-day) JWT and exposes
/// `POST /auth/refresh` to rotate it. There is no separate refresh token —
/// rotation is gated by the existing access token still being unexpired and
/// the device row's `jti` matching. We persist the whole record so the app
/// can decide *before* sending a request whether to rotate proactively.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.expiresAt,
    required this.userId,
    required this.deviceId,
  });

  factory AuthSession.fromJson(Map<String, Object?> json) => AuthSession(
    accessToken: json['access_token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
    userId: json['user_id'] as String,
    deviceId: json['device_id'] as String,
  );

  /// JSON-encoded form for storage in a [SecureKeyStore].
  static AuthSession decode(String raw) =>
      AuthSession.fromJson(jsonDecode(raw) as Map<String, Object?>);

  final String accessToken;
  final DateTime expiresAt;
  final String userId;
  final String deviceId;

  Map<String, Object?> toJson() => <String, Object?>{
    'access_token': accessToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'user_id': userId,
    'device_id': deviceId,
  };

  String encode() => jsonEncode(toJson());

  AuthSession withRotatedToken({
    required String accessToken,
    required DateTime expiresAt,
  }) => AuthSession(
    accessToken: accessToken,
    expiresAt: expiresAt,
    userId: userId,
    deviceId: deviceId,
  );

  /// True when [now] is past [expiresAt]. The backend rejects 401 in that
  /// case anyway; checking client-side lets us skip the round-trip and route
  /// straight to the login screen.
  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now().toUtc()).isBefore(expiresAt);

  /// Time remaining until expiry. Negative if already expired.
  Duration remaining({DateTime? now}) =>
      expiresAt.difference(now ?? DateTime.now().toUtc());
}
