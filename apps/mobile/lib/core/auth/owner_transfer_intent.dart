import 'auth_session.dart';

/// Stored only in SecureKeyStore. Never write these snapshots to SQLite or logs.
class OwnerIdentitySnapshot {
  const OwnerIdentitySnapshot({
    required this.mode,
    required this.session,
    required this.deviceId,
  });

  final String mode;
  final AuthSession? session;
  final String deviceId;

  Map<String, Object?> toJson() => {
    'mode': mode,
    'session': session?.encode(),
    'device_id': deviceId,
  };

  factory OwnerIdentitySnapshot.fromJson(Map<String, dynamic> json) {
    final mode = json['mode'] as String;
    final encoded = json['session'] as String?;
    final session = encoded == null ? null : AuthSession.decode(encoded);
    final deviceId = json['device_id'] as String;
    if (!const {'unset', 'cloud', 'local_only'}.contains(mode) ||
        (mode == 'local_only' && session != null) ||
        deviceId.isEmpty) {
      throw const FormatException('Invalid identity snapshot');
    }
    return OwnerIdentitySnapshot(
      mode: mode,
      session: session,
      deviceId: deviceId,
    );
  }
}

class OwnerTransferIntent {
  const OwnerTransferIntent({
    required this.id,
    required this.from,
    required this.to,
    required this.previous,
    required this.target,
  });

  final String id;
  final String from;
  final String to;
  final OwnerIdentitySnapshot previous;
  final OwnerIdentitySnapshot target;

  Map<String, Object?> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'previous': previous.toJson(),
    'target': target.toJson(),
  };

  factory OwnerTransferIntent.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final from = json['from'] as String;
    final to = json['to'] as String;
    if (id.isEmpty || from.isEmpty || to.isEmpty || from == to) {
      throw const FormatException('Invalid owner transfer');
    }
    return OwnerTransferIntent(
      id: id,
      from: from,
      to: to,
      previous: OwnerIdentitySnapshot.fromJson(
        json['previous'] as Map<String, dynamic>,
      ),
      target: OwnerIdentitySnapshot.fromJson(
        json['target'] as Map<String, dynamic>,
      ),
    );
  }
}
