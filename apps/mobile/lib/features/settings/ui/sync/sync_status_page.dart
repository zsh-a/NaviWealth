import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../../core/auth/providers.dart';
import '../../../../core/config/providers.dart';
import '../../../../core/sync/local_table_counts.dart';
import '../../../../core/sync/providers.dart';
import '../../../../core/sync/sync_status.dart';
import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

part 'status/body.dart';
part 'status/diagnostics.dart';
part 'status/shared.dart';
part 'status/status_cards.dart';

/// Diagnostic page surfacing the current sync engine state at a glance:
/// hero status, three quick-read stat tiles, and a collapsible details
/// panel. Reachable from Settings > Sync.
class SyncStatusPage extends ConsumerWidget {
  const SyncStatusPage({super.key, this.now});

  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final eventAsync = ref.watch(syncStatusEventStreamProvider);
    return AppPageScaffold(
      title: l10n.syncStatusTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.refreshCw),
          onPress: () => _triggerSyncNow(ref),
        ),
      ],
      childPad: false,
      child: eventAsync.whenOrLoading(
        context: context,
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s24),
            child: Text(userSafeErrorMessage(context, e)),
          ),
        ),
        data: (event) => _Body(event: event, now: now),
      ),
    );
  }
}

Future<void> _triggerSyncNow(WidgetRef ref) async {
  final scheduler = await ref.read(syncSchedulerProvider.future);
  await scheduler?.triggerNow();
  ref.invalidate(syncCursorProvider);
  ref.invalidate(syncOutboxDepthProvider);
  ref.invalidate(localTableCountsProvider);
}
