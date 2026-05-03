import 'models/holding_snapshot.dart';
import 'models/lot.dart';

/// Public contract for holdings derived from the forward ledger.
///
/// Implementations read `journal_entries` / `postings` and price the open
/// lots through the `prices` time-series. Callers should treat holdings as
/// a read model over postings.
abstract class HoldingService {
  /// Holdings as of [asOf].
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf);

  /// Raw open lots as of [asOf], before pricing.
  Future<List<Lot>> lotsAt(DateTime asOf);

  /// Materialize the lot inventory at end of [day]. Current production
  /// implementation computes this on demand and returns the derived
  /// snapshot; persisted snapshot storage can be added when the postings
  /// read model needs it.
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day);

  /// Invalidate cached snapshots at or after [from]. No-op until persisted
  /// postings-derived snapshots exist.
  Future<void> invalidateFrom(DateTime from);
}
