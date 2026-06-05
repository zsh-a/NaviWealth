import 'auth_session.dart';

// -- State types ----------------------------------------------------------

/// The three observable states of the auth subsystem. Watched by
/// [AuthRouteGuard] (router redirect) and the UI (login progress feedback).
sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthLoggedOut extends AuthState {
  const AuthLoggedOut({this.reason});

  /// Optional one-shot reason for ending the previous session — e.g.
  /// `sessionExpired`, `loggedOut`. Cleared once the login screen reads it.
  final LoggedOutReason? reason;
}

class AuthLoggedIn extends AuthState {
  const AuthLoggedIn(this.session);
  final AuthSession session;
}

/// Account-less local-only mode. The user opted out of the cloud account at
/// onboarding; sync is inert, the outbox is a no-op, and mutations are
/// stamped with synthetic user/device ids. The router treats this state
/// equivalently to [AuthLoggedIn] for redirect purposes.
class AuthLocalOnly extends AuthState {
  const AuthLocalOnly();
}

enum LoggedOutReason { sessionExpired, manuallyLoggedOut }
