/// Cross-domain sync outbox provider (`docs/lifeos-shell.md` §8).
///
/// Every domain repository (Finance / Health / future domains) writes
/// to the same `op_outbox` table that the [SyncEngine] drains on push.
/// Living in `core/sync/` rather than under one domain's tree means
/// HealthOS and future domains can register their writes without
/// importing `features/finance/`.
///
/// In local-only mode the user opted out of sync entirely; the outbox
/// becomes a no-op so repository writes don't accumulate ops that will
/// never be drained.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../auth/providers.dart';
import '../persistence/providers.dart';
import 'drift_sync_storage.dart';
import 'op_outbox.dart';

final outboxStoreProvider = FutureProvider<OutboxStore>((ref) async {
  final auth = ref.watch(authStateProvider);
  if (auth is AuthLocalOnly) {
    return const NoopOutboxStore();
  }
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftOutboxStore(db);
});
