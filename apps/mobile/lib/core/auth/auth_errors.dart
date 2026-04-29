/// Domain-level auth failures. Mapped from HTTP responses by the API client
/// so call-sites (login form, devices page) can switch on the kind without
/// caring about Dio internals.
enum AuthErrorKind {
  /// Server confirmed the email/password combination doesn't grant access.
  /// Includes the case where the email doesn't exist — the backend deliberately
  /// burns argon2 cost on misses so we can't distinguish here either.
  invalidCredentials,

  /// Bearer token rejected by the server — expired, revoked, or device
  /// row gone. UI must clear the local session and route to /login.
  unauthorized,

  /// Connection timeout, DNS, offline, etc. UI should show retry affordance.
  network,

  /// Request was malformed (4xx other than 401). Usually a programming bug;
  /// surfaces as a generic error in UI.
  badRequest,

  /// 5xx — backend is down. UI offers retry; auto-retry is *not* applied so
  /// users don't pile on during incidents.
  server,

  /// Anything we don't recognise. Treated like [server] in the UI.
  unknown,
}

class AuthException implements Exception {
  AuthException(this.kind, {this.statusCode, this.message, this.cause});

  final AuthErrorKind kind;
  final int? statusCode;
  final String? message;
  final Object? cause;

  @override
  String toString() {
    final parts = <String>['AuthException(${kind.name}'];
    if (statusCode != null) parts.add('status=$statusCode');
    if (message != null) parts.add('"$message"');
    return '${parts.join(', ')})';
  }
}
