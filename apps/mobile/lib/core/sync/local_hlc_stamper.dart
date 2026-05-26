import '../../core/persistence/app_database.dart';
import '../../data/domain/hlc.dart';
import 'drift_sync_storage.dart';

/// Account-less HLC stamper used by the local-only mode.
///
/// Mirrors [SyncEngine.stampHlc] but doesn't require an authenticated
/// session — the device id is the locally-generated identity (not a
/// backend-issued one) and there's no sync engine to coordinate with.
class LocalHlcStamper {
  LocalHlcStamper({required AppDatabase db, required this.deviceId})
    : _cursors = DriftCursorStore(db);

  final DriftCursorStore _cursors;
  final String deviceId;

  Future<Hlc> stamp({int? overrideNowMillis}) async {
    final last = await _cursors.readLocalHlc() ?? Hlc.zero(deviceId);
    final next = Hlc.tick(
      lastSeen: last,
      nowMillis: overrideNowMillis ?? DateTime.now().millisecondsSinceEpoch,
    );
    await _cursors.writeLocalHlc(next);
    return next;
  }
}
