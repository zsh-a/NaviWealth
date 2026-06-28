/// Cross-domain accessor for the active user's id (D-1.2 follow-up).
///
/// Shell-level code (Memory Layer tools, sync engine, AI runtime)
/// needs to scope reads/writes to a single user without taking a hard
/// dependency on FinanceOS. This provider used to live next to the
/// Finance write-side helpers (`features/finance/data/repositories/
/// mutation_context.dart`); D-1.2 extracted the cross-domain piece so
/// `core/` can stop importing `features/`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';
import 'providers.dart';

/// Local-only mode synthetic user id — mirrors the value used by the
/// Finance write side.
const String kLocalOnlyUserId = 'local-user';

/// Returns the active user's id. Override in tests to inject a fixed
/// value.
final currentUserIdProvider = Provider<Future<String> Function()>((ref) {
  final auth = ref.watch(authStateProvider);
  return () async {
    if (auth is AuthLoggedIn) return auth.session.userId;
    if (auth is AuthLocalOnly) return kLocalOnlyUserId;
    throw StateError(
      'currentUserIdProvider requires an authenticated session.',
    );
  };
});

/// Synchronous active-user id for UI scoping.
///
/// Returns the cloud session's user id when logged in, the synthetic
/// [kLocalOnlyUserId] in local-only mode, or `null` before auth settles.
///
/// The on-device AI is account-less (device-only runtime, the user's own
/// key — see `docs/ai/ai-architecture.md`): chat history is partitioned by
/// this id in *both* modes, so local-only users must NOT be sent to a
/// login wall. Surfaces that previously gated on [authSessionProvider]
/// (which is null in local-only mode) should watch this instead.
final activeUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth is AuthLoggedIn) return auth.session.userId;
  if (auth is AuthLocalOnly) return kLocalOnlyUserId;
  // Fall back to the session reader so surfaces that only wire up the
  // session (widget tests, or the brief window before the controller
  // settles) still resolve a user id.
  return ref.watch(authSessionProvider)?.userId;
});
