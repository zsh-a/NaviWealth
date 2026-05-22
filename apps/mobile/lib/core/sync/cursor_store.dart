import '../../data/domain/hlc.dart';

/// Persists the SyncEngine's two pieces of state (`docs/sync-v2.md` §7.5).
///
/// `seq` — the pull cursor. The next sync sends `since = seq`. A monotonic
/// integer the server assigns; `0` before the first sync.
///
/// `localHlc` — the HLC state used to stamp new local writes. Persisted so a
/// session whose physical clock briefly went backwards never re-issues a
/// version below rows already on disk.
abstract class CursorStore {
  Future<int> readSeq();
  Future<void> writeSeq(int seq);

  Future<Hlc?> readLocalHlc();
  Future<void> writeLocalHlc(Hlc hlc);
}
