import '../../data/domain/hlc.dart';

/// Persists the SyncEngine's two pieces of clock state.
///
/// `cursor` — `last_pulled_hlc`. The next pull asks for `since = cursor`.
/// Persisted **per user**, not per device (`docs/sync-protocol.md` §7.4).
///
/// `localHlc` — the HLC state used to stamp new local ops. Persisted so
/// that a long-offline session whose physical clock briefly went backwards
/// doesn't re-issue ops with HLCs lower than rows already on disk.
abstract class CursorStore {
  Future<Hlc?> readCursor();
  Future<void> writeCursor(Hlc hlc);

  Future<Hlc?> readLocalHlc();
  Future<void> writeLocalHlc(Hlc hlc);
}
