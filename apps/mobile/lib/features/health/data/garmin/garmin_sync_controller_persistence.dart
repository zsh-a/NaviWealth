part of 'garmin_sync_controller.dart';

mixin GarminSyncControllerPersistenceMixin on Notifier<GarminSyncState> {
  /// Persist a HealthSnapshot JSON to the local Drift database.
  Future<GarminWriteResult?> _persistSnapshot(String? snapshotJson) async {
    final logger = AppLogger.instance;
    if (snapshotJson == null || snapshotJson.isEmpty) {
      logger.w('HealthOS Garmin persist skipped: empty snapshotJson');
      return null;
    }
    try {
      logger.i('HealthOS Garmin persist start: bytes=${snapshotJson.length}');
      final writer = await ref.read(garminSnapshotWriterProvider.future);
      return await writer.writeSnapshotJson(snapshotJson);
    } catch (e) {
      logger.e('HealthOS Garmin persist exception', error: e);
      return GarminWriteResult(
        upserted: 0,
        unchanged: 0,
        errors: [GarminSyncIssue.persistFailed(e).message],
      );
    }
  }

  List<GarminSyncIssue> _snapshotPersistIssues({
    required int metricsCount,
    required bool hasSnapshotJson,
    required GarminWriteResult? writeResult,
  }) {
    if (metricsCount <= 0) return const <GarminSyncIssue>[];
    if (!hasSnapshotJson) {
      return [GarminSyncIssue.noSnapshot()];
    }
    if (writeResult == null) {
      return [GarminSyncIssue.notPersisted()];
    }
    if (writeResult.total == 0) {
      return [GarminSyncIssue.unsupportedSnapshot()];
    }
    return const <GarminSyncIssue>[];
  }
}
