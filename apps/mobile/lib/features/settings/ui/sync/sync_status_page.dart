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
class SyncStatusPage extends ConsumerStatefulWidget {
  const SyncStatusPage({super.key, this.now});

  final DateTime? now;

  @override
  ConsumerState<SyncStatusPage> createState() => _SyncStatusPageState();
}

class _SyncStatusPageState extends ConsumerState<SyncStatusPage> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final eventAsync = ref.watch(syncStatusEventStreamProvider);
    return AppPageScaffold(
      title: l10n.syncStatusTitle,
      actions: [
        FHeaderAction(
          icon: _syncing
              ? const SizedBox.square(
                  dimension: AppIconSizes.h18,
                  child: FCircularProgress(
                    size: FCircularProgressSizeVariant.xs,
                  ),
                )
              : const Icon(FLucideIcons.refreshCw),
          semanticsLabel: l10n.syncStatusActionSyncNow,
          onPress: _syncing ? null : _triggerSyncNow,
        ),
      ],
      childPad: false,
      child: eventAsync.when(
        loading: () =>
            const AppListPageSkeleton(showControls: false, itemCount: 4),
        error: (error, stackTrace) => AppEmptyState.error(
          title: l10n.commonLoadFailed,
          message: userSafeErrorMessage(context, error, stackTrace: stackTrace),
          retryLabel: l10n.commonRetry,
          onRetry: () => ref.invalidate(syncStatusEventStreamProvider),
        ),
        data: (event) => _Body(
          event: event,
          now: widget.now,
          onSyncNow: _syncing ? null : _triggerSyncNow,
        ),
      ),
    );
  }

  Future<void> _triggerSyncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final scheduler = await ref.read(syncSchedulerProvider.future);
      await scheduler?.triggerNow();
      ref.invalidate(syncCursorProvider);
      ref.invalidate(syncOutboxDepthProvider);
      ref.invalidate(localTableCountsProvider);
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppMessenger.show(
        context,
        ToastKind.error,
        userSafeErrorMessage(context, error, stackTrace: stackTrace),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }
}
