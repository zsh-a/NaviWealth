part of 'garmin_sync_controller.dart';

mixin GarminSyncControllerSyncMixin
    on
        Notifier<GarminSyncState>,
        GarminSyncControllerSessionMixin,
        GarminSyncControllerRangeMixin,
        GarminSyncControllerPersistenceMixin {
  @override
  GarminBridge get _bridge;
  @override
  StreamSubscription<GarminSyncProgress>? get _syncSub;
  @override
  set _syncSub(StreamSubscription<GarminSyncProgress>? value);

  /// Sync recent data with streaming progress updates.
  Future<void> syncNow({Duration window = const Duration(days: 30)}) =>
      _syncNow(window: window, allowCredentialRecovery: true);

  Future<void> _syncNow({
    required Duration window,
    required bool allowCredentialRecovery,
  }) async {
    final now = DateTime.now().toUtc();
    state = GarminSyncing(startedAt: now);
    final logger = AppLogger.instance;
    final region = ref.read(garminRegionProvider);

    // Cancel any previous sync stream.
    await _syncSub?.cancel();

    try {
      final canSync = await _ensureSessionForSync(logger);
      if (!canSync) {
        if (state is! GarminError) state = const GarminInitial();
        return;
      }
      final ranges = await _missingGarminRanges(now: now, window: window);
      logger.i(
        'HealthOS Garmin sync start: region=${region.label} '
        'windowDays=${window.inDays} missingRanges=${ranges.length} '
        'missingDays=${ranges.fold<int>(0, (sum, range) => sum + range.days)} '
        'ranges=${ranges.map((r) => r.label).toList()}',
      );

      if (ranges.isEmpty) {
        logger.i('HealthOS Garmin sync skipped: no missing days');
        state = GarminConnected(lastSyncAt: now);
        return;
      }

      var totalPersisted = 0;
      final allIssues = <GarminSyncIssue>[];
      for (var index = 0; index < ranges.length; index += 1) {
        final result = await _syncRange(
          range: ranges[index],
          startedAt: now,
          rangeIndex: index,
          rangeCount: ranges.length,
          logger: logger,
        );
        totalPersisted += result.persistedMetrics;
        allIssues.addAll(result.issues);
        final fatalIssues = allIssues.fatal;
        if (fatalIssues.isNotEmpty) {
          if (fatalIssues.requiresReconnect) {
            await _clearStaleSession();
            logger.w('HealthOS Garmin stale session cleared after auth error');
            if (allowCredentialRecovery) {
              final recovered = await _recoverWithSavedCredentials(
                logger: logger,
              );
              if (recovered) {
                await _syncNow(window: window, allowCredentialRecovery: false);
                return;
              }
              if (state is GarminPendingMfa) return;
              if (state is GarminError) return;
            }
          }
          logger.w(
            'HealthOS Garmin sync failed: ${fatalIssues.first.logLabel}',
          );
          state = GarminError(fatalIssues.first);
          return;
        }
      }

      await _persistSession();
      logger.i('HealthOS Garmin sync success: totalMetrics=$totalPersisted');
      state = GarminConnected(lastSyncAt: now, totalMetrics: totalPersisted);
    } catch (e) {
      logger.e('HealthOS Garmin sync exception', error: e);
      final issue = GarminSyncIssue.fromLegacyMessage(e.toString());
      if (issue.requiresReconnect) {
        await _clearStaleSession();
        if (allowCredentialRecovery) {
          final recovered = await _recoverWithSavedCredentials(logger: logger);
          if (recovered) {
            await _syncNow(window: window, allowCredentialRecovery: false);
            return;
          }
          if (state is GarminPendingMfa) return;
          if (state is GarminError) return;
        }
      }
      state = GarminError(issue);
    }
  }

  Future<_GarminRangeSyncResult> _syncRange({
    required _GarminDateRange range,
    required DateTime startedAt,
    required int rangeIndex,
    required int rangeCount,
    required AppLogger logger,
  }) async {
    final completer = Completer<_GarminRangeSyncResult>();
    GarminSyncing? latest;
    _syncSub = _bridge
        .syncRangeWithProgress(range.from, range.to)
        .listen(
          (progress) {
            final issues = parseGarminSyncIssues(progress.errors);
            logger.i(
              'HealthOS Garmin progress: range=${rangeIndex + 1}/$rangeCount '
              '${range.label} phase=${progress.phase} '
              'current=${progress.current}/${progress.total} '
              'metrics=${progress.metricsCount} '
              'issues=${issues.length} '
              'snapshotBytes=${progress.snapshotJson?.length ?? 0}',
            );
            if (issues.isNotEmpty) {
              logger.w(
                'HealthOS Garmin progress issues: '
                '${issues.map((issue) => issue.logLabel).toList()}',
              );
            }
            latest = GarminSyncing(
              startedAt: startedAt,
              phase: progress.phase,
              currentDay: progress.current,
              totalDays: progress.total,
              metricsCount: progress.metricsCount,
              issues: issues,
              snapshotJson: progress.snapshotJson ?? latest?.snapshotJson,
            );
            state = latest!;
          },
          onDone: () async {
            final s = latest;
            if (s == null) {
              completer.complete(
                const _GarminRangeSyncResult(
                  persistedMetrics: 0,
                  issues: <GarminSyncIssue>[],
                ),
              );
              return;
            }
            logger.i(
              'HealthOS Garmin stream done: range=${range.label} '
              'phase=${s.phase} metrics=${s.metricsCount} '
              'issues=${s.issues.length} '
              'snapshotBytes=${s.snapshotJson?.length ?? 0}',
            );
            final writeResult = await _persistSnapshot(s.snapshotJson);
            logger.i(
              'HealthOS Garmin persist result: range=${range.label} '
              'total=${writeResult?.total ?? 0} '
              'upserted=${writeResult?.upserted ?? 0} '
              'unchanged=${writeResult?.unchanged ?? 0} '
              'errors=${writeResult?.errors ?? const <String>[]}',
            );
            ref.invalidate(healthMetricRepositoryProvider);
            final issues = <GarminSyncIssue>[
              ...s.issues,
              ..._snapshotPersistIssues(
                metricsCount: s.metricsCount,
                hasSnapshotJson:
                    s.snapshotJson != null && s.snapshotJson!.isNotEmpty,
                writeResult: writeResult,
              ),
              if (writeResult != null)
                ...writeResult.errors.map(GarminSyncIssue.fromLegacyMessage),
            ];
            completer.complete(
              _GarminRangeSyncResult(
                persistedMetrics: writeResult?.total ?? s.metricsCount,
                issues: issues,
              ),
            );
          },
          onError: (Object e) {
            logger.e('HealthOS Garmin stream error', error: e);
            completer.complete(
              _GarminRangeSyncResult(
                persistedMetrics: 0,
                issues: [GarminSyncIssue.fromLegacyMessage(e.toString())],
              ),
            );
          },
          cancelOnError: true,
        );

    return completer.future;
  }
}

class _GarminRangeSyncResult {
  const _GarminRangeSyncResult({
    required this.persistedMetrics,
    required this.issues,
  });

  final int persistedMetrics;
  final List<GarminSyncIssue> issues;
}
