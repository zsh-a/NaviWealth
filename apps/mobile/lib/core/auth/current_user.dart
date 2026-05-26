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

import '../../features/auth/data/auth_controller.dart';

/// Local-only mode synthetic user id — mirrors the value used by the
/// Finance write side.
const String kLocalOnlyUserId = 'local-user';

/// Returns the active user's id. Override in tests to inject a fixed
/// value.
final currentUserIdProvider = Provider<Future<String> Function()>((ref) {
  final auth = ref.watch(authControllerProvider).value;
  return () async {
    if (auth is AuthLoggedIn) return auth.session.userId;
    if (auth is AuthLocalOnly) return kLocalOnlyUserId;
    throw StateError(
      'currentUserIdProvider requires an authenticated session.',
    );
  };
});
