import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../auth/auth_state.dart';
import '../auth/providers.dart';
import '../sync/providers.dart';
import '../sync/sync_status.dart';

bool syncNeedsAttention(SyncStatusEvent? event) =>
    event?.status == SyncStatus.failed ||
    (event?.status == SyncStatus.offline && (event?.outboxDepth ?? 0) > 0);

/// Local-only workspaces have no remote sync to repair.
final syncAttentionProvider = Provider<SyncStatusEvent?>((ref) {
  if (ref.watch(authStateProvider) is! AuthLoggedIn) return null;
  final event = ref.watch(syncStatusEventStreamProvider).value;
  return syncNeedsAttention(event) ? event : null;
});

String syncOverviewMessage(AppLocalizations l10n, SyncStatusEvent? event) =>
    switch (event?.status) {
      SyncStatus.failed => l10n.syncLocalSavedNeedsAttention,
      SyncStatus.offline when (event?.outboxDepth ?? 0) > 0 =>
        l10n.syncLocalSavedPending(event!.outboxDepth!),
      SyncStatus.offline => l10n.syncStatusHeadlineOffline,
      SyncStatus.syncing => l10n.syncStatusHeadlineSyncing,
      SyncStatus.online when (event?.outboxDepth ?? 0) > 0 =>
        l10n.syncLocalSavedPending(event!.outboxDepth!),
      SyncStatus.online => l10n.syncStatusHeadlineOnline,
      _ => l10n.syncStatusHeadlineIdle,
    };
