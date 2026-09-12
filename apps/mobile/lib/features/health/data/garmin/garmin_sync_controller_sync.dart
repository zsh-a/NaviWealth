part of 'garmin_sync_controller.dart';

extension _GarminSessionSync on _GarminSession {
  Future<HealthRefreshSourceResult> refresh({
    required Duration window,
    required bool automatic,
  }) {
    if (refreshFuture != null) return refreshFuture!;
    cancelled = false;
    final future = _prepareRefresh(window: window, automatic: automatic);
    refreshFuture = future.whenComplete(() => refreshFuture = null);
    return refreshFuture!;
  }

  Future<HealthRefreshSourceResult> _prepareRefresh({
    required Duration window,
    required bool automatic,
  }) async {
    await restore();
    return queue.run(() async {
      if (!active || cancelled || authenticating) return _garminSkipped;
      if (state is GarminInitial) return _garminSkipped;
      if (state is GarminPendingMfa) return _failure('mfa_required');
      if (state case GarminError(:final issue) when issue.requiresReconnect) {
        return _failure(issue.code);
      }
      final saved = status;
      final now = clock().toUtc();
      // Manual refresh bypasses freshness, but never a server rate-limit cooldown.
      if (saved?.nextRetryAt case final DateTime retryAt
          when retryAt.isAfter(now) &&
              (automatic || saved?.errorCode == 'rate_limited')) {
        return _garminSkipped;
      }
      final checked = saved?.lastCheckedAt;
      if (automatic &&
          saved?.errorCode == null &&
          checked != null &&
          now.difference(checked) < const Duration(minutes: 30)) {
        return _garminSkipped;
      }
      return _runRefresh(
        window: window,
        automatic: automatic,
        recoverAuth: true,
      );
    });
  }

  Future<HealthRefreshSourceResult> _runRefresh({
    required Duration window,
    required bool automatic,
    required bool recoverAuth,
  }) async {
    final attemptedAt = clock().toUtc();
    final previous = restoredState();
    var changed = 0;
    var unchanged = 0;
    var checked = false;
    final issues = <GarminSyncIssue>[];
    try {
      if (!await ensureSession()) {
        if (state is GarminPendingMfa) return _failure('mfa_required');
        if (state case GarminError(:final issue)) {
          await recordRefresh(
            attemptedAt,
            changed: 0,
            unchanged: 0,
            issues: [issue],
            checked: false,
          );
          return _failure(issue.code);
        }
        state = const GarminInitial();
        return _garminSkipped;
      }
      if (cancelled) throw const _GarminCancelled();
      final localNow = clock();
      final days = statusStore.checkedDays(owner, region.wire);
      final ranges = planGarminRefresh(
        localNow: localNow,
        checkedDays: days,
        window: window,
      );
      for (final range in ranges) {
        checkActive();
        if (cancelled) throw const _GarminCancelled();
        state = GarminSyncing(
          startedAt: attemptedAt,
          automatic: automatic,
          previous: previous,
        );
        final result = await _readRange(
          range,
          attemptedAt,
          automatic,
          previous,
        );
        changed += result.upserted;
        unchanged += result.unchanged;
        checked |= result.checked;
        issues.addAll(result.issues);
        // Only daily-data success is a history checkpoint. Optional unsupported
        // enrichments can be revisited at the normal weekly reconciliation.
        if (result.issues.every(
          (issue) =>
              issue.code == 'endpoint_unavailable' &&
              const {
                'activities',
                'weight',
                'training_status',
              }.contains(issue.endpoint),
        )) {
          for (final day in range.dates) {
            days[_garminDayKey(day)] = clock().toUtc();
          }
          final cutoff = _garminDayKey(
            garminCalendarDay(localNow).subtract(const Duration(days: 90)),
          );
          days.removeWhere((day, _) => day.compareTo(cutoff) < 0);
          await guarded(statusStore.saveCheckedDays(owner, region.wire, days));
        } else {
          // A newer partial attempt invalidates older completion markers, even
          // when a recent day subsequently ages out into historical backfill.
          for (final day in range.dates) {
            days.remove(_garminDayKey(day));
          }
          await guarded(statusStore.saveCheckedDays(owner, region.wire, days));
        }
        if (issues.requiresReconnect && recoverAuth) {
          await guarded(
            tokenStore.clearSession(ownerUserId: owner, region: region),
          );
          initialized = false;
          if (await recoverCredentials()) {
            return await _runRefresh(
              window: window,
              automatic: automatic,
              recoverAuth: false,
            );
          }
          if (state is GarminPendingMfa) return _failure('mfa_required');
        }
        // Do not amplify an outage or rate limit with historical requests.
        if (result.issues.any(
          (issue) =>
              issue.isFatal ||
              issue.code == 'rate_limited' ||
              issue.code == 'endpoint_failed',
        )) {
          break;
        }
      }
      checkActive();
      if (cancelled) throw const _GarminCancelled();
      await persistSession();
      await recordRefresh(
        attemptedAt,
        changed: changed,
        unchanged: unchanged,
        issues: issues,
        checked: checked,
      );
      final fatal = issues.fatal;
      if (fatal.isNotEmpty) {
        state = GarminError(fatal.first);
      } else {
        state = restoredState();
      }
      return HealthRefreshSourceResult(
        source: HealthRefreshSource.garmin,
        outcome: fatal.isNotEmpty
            ? HealthRefreshOutcome.failed
            : issues.isNotEmpty
            ? HealthRefreshOutcome.partial
            : HealthRefreshOutcome.synced,
        imported: changed,
        unchanged: unchanged,
        errorCode: issues.primary?.code,
      );
    } on _GarminCancelled {
      if (active) {
        // Preserve the last completed check, but avoid immediately restarting a
        // user-cancelled or background-interrupted import on the next timer tick.
        await recordCancellation(attemptedAt);
        state = restoredState();
      }
      return const HealthRefreshSourceResult(
        source: HealthRefreshSource.garmin,
        outcome: HealthRefreshOutcome.skipped,
        errorCode: 'cancelled',
      );
    } on Object catch (error) {
      if (!active) return _garminSkipped;
      final issue = GarminSyncIssue.fromLegacyMessage(error.toString());
      await recordRefresh(
        attemptedAt,
        changed: changed,
        unchanged: unchanged,
        issues: [issue],
        checked: false,
      );
      state = GarminError(issue);
      return _failure(issue.code);
    }
  }

  Future<_GarminRangeResult> _readRange(
    GarminDateRange range,
    DateTime startedAt,
    bool automatic,
    GarminConnected previous,
  ) async {
    String? snapshot;
    var count = 0;
    var done = false;
    final issues = <GarminSyncIssue>[];
    nativeCancellation = null;
    streaming = true;
    try {
      await for (final progress in bridge.syncRangeWithProgress(
        range.from,
        range.to,
      )) {
        // Drain until terminal completion after cancellation so another session
        // cannot replace the process-global native client while it is in use.
        if (!active || cancelled) {
          if (progress.phase == 'starting') {
            await signalCancellation(nativeStarted: true);
          }
          continue;
        }
        if (progress.phase == 'cancelled') {
          cancelled = true;
          continue;
        }
        snapshot = progress.snapshotJson ?? snapshot;
        count = progress.metricsCount;
        if (progress.phase == 'done') done = true;
        issues
          ..clear()
          ..addAll(parseGarminSyncIssues(progress.errors));
        state = GarminSyncing(
          startedAt: startedAt,
          phase: progress.phase,
          currentDay: progress.current,
          totalDays: progress.total,
          metricsCount: count,
          issues: List.unmodifiable(issues),
          automatic: automatic,
          previous: previous,
        );
      }
    } finally {
      streaming = false;
      await nativeCancellation;
    }
    checkActive();
    if (cancelled) throw const _GarminCancelled();
    if (!done || snapshot == null) {
      return _GarminRangeResult(0, 0, [
        ...issues,
        if (issues.fatal.isEmpty) GarminSyncIssue.noSnapshot(),
      ], checked: false);
    }
    final written = await persistSnapshot(snapshot);
    checkActive();
    if (cancelled) throw const _GarminCancelled();
    if (written.total == 0 && count > 0) {
      issues.add(GarminSyncIssue.unsupportedSnapshot());
    }
    issues.addAll(written.errors.map(GarminSyncIssue.fromLegacyMessage));
    // Publish each completed batch; Today need not wait for historical backfill.
    if (written.upserted > 0) ref.invalidate(healthMetricRepositoryProvider);
    return _GarminRangeResult(written.upserted, written.unchanged, issues);
  }

  HealthRefreshSourceResult _failure(String code) => HealthRefreshSourceResult(
    source: HealthRefreshSource.garmin,
    outcome: HealthRefreshOutcome.failed,
    errorCode: code,
  );
}

class _GarminRangeResult {
  const _GarminRangeResult(
    this.upserted,
    this.unchanged,
    this.issues, {
    this.checked = true,
  });
  final int upserted;
  final int unchanged;
  final List<GarminSyncIssue> issues;
  final bool checked;
}
