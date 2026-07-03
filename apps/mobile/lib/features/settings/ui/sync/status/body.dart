part of '../sync_status_page.dart';

class _Body extends ConsumerWidget {
  const _Body({required this.event, required this.now});

  final SyncStatusEvent event;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outboxAsync = ref.watch(syncOutboxDepthProvider);
    final cursorAsync = ref.watch(syncCursorProvider);
    final countsAsync = ref.watch(localTableCountsProvider);
    final session = ref.watch(authSessionProvider);
    final config = ref.watch(appConfigProvider);

    final localTotal = countsAsync.value?.values.fold<int>(0, (a, b) => a + b);
    final relativeNow = now ?? DateTime.now();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.s16).copyWith(
        bottom:
            const EdgeInsets.all(AppSpacing.s16).bottom +
            AppSpacing.s64 +
            MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _HeroCard(
          event: event,
          now: relativeNow,
          onSyncNow: session == null ? null : () => _triggerSyncNow(ref),
        ),
        const SizedBox(height: AppSpacing.s12),
        _StatGrid(
          pending: outboxAsync.value,
          localTotal: localTotal,
          lastSyncAt: event.lastSuccessAt,
          now: relativeNow,
        ),
        if (event.lastError != null) ...[
          const SizedBox(height: AppSpacing.s12),
          _ErrorCard(message: event.lastError!),
        ],
        if (event.conflicts.hasFindings) ...[
          const SizedBox(height: AppSpacing.s12),
          _ConflictCard(diagnostics: event.conflicts),
        ],
        const SizedBox(height: AppSpacing.s12),
        _DiagnosticsCard(
          event: event,
          cursor: cursorAsync.value,
          deviceId: session?.deviceId,
          apiBaseUrl: kDebugMode ? config.apiBaseUrl : null,
          now: relativeNow,
        ),
        if (kDebugMode) ...[
          const SizedBox(height: AppSpacing.s12),
          _LocalCountsCard(counts: countsAsync.value),
        ],
      ],
    );
  }
}
