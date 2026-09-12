part of 'garmin_sync_controller.dart';

extension _GarminSessionPersistence on _GarminSession {
  Future<GarminWriteResult> persistSnapshot(String snapshot) async {
    final writer = await guarded(ref.read(garminSnapshotWriterProvider.future));
    if (cancelled) throw const _GarminCancelled();
    return guarded(
      writer.writeSnapshotJson(
        snapshot,
        beforeCommit: () {
          checkActive();
          if (cancelled) throw const _GarminCancelled();
        },
        expectedOwnerUserId: owner,
      ),
    );
  }

  Future<void> recordRefresh(
    DateTime attemptedAt, {
    required int changed,
    required int unchanged,
    required List<GarminSyncIssue> issues,
    required bool checked,
  }) async {
    checkActive();
    final previous = status;
    final now = clock().toUtc();
    final transientFailure = issues.any(
      (issue) =>
          issue.isFatal ||
          issue.action == GarminSyncIssueAction.retry ||
          issue.action == GarminSyncIssueAction.retryLater,
    );
    final failures = transientFailure ? (previous?.failureCount ?? 0) + 1 : 0;
    final retryMinutes = issues.any((issue) => issue.code == 'rate_limited')
        ? 30
        : transientFailure
        ? (5 * (1 << (failures - 1).clamp(0, 4))).clamp(5, 60)
        : 30;
    await guarded(
      statusStore.write(
        ownerUserId: owner,
        region: region.wire,
        lastAttemptAt: attemptedAt,
        lastSuccessAt: checked && issues.isEmpty
            ? now
            : previous?.lastSuccessAt,
        lastCheckedAt: checked ? now : previous?.lastCheckedAt,
        totalMetrics: changed,
        unchanged: unchanged,
        partial: checked && issues.isNotEmpty && issues.fatal.isEmpty,
        errorCode: issues.primary?.code,
        failureCount: failures,
        nextRetryAt: issues.isEmpty
            ? null
            : now.add(Duration(minutes: retryMinutes)),
      ),
    );
  }

  Future<void> recordCancellation(DateTime attemptedAt) async {
    final previous = status;
    await guarded(
      statusStore.write(
        ownerUserId: owner,
        region: region.wire,
        lastAttemptAt: attemptedAt,
        lastSuccessAt: previous?.lastSuccessAt,
        lastCheckedAt: previous?.lastCheckedAt,
        totalMetrics: previous?.totalMetrics ?? 0,
        unchanged: previous?.unchanged ?? 0,
        errorCode: previous?.errorCode,
        partial: previous?.partial ?? false,
        failureCount: previous?.failureCount ?? 0,
        nextRetryAt: clock().toUtc().add(const Duration(minutes: 30)),
      ),
    );
  }
}
