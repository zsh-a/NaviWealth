import 'models/holding_snapshot.dart';
import 'models/lot.dart';

enum HoldingValuationIssueCause { missingFx, missingPrice, currencyMismatch }

class HoldingValuationIssue {
  const HoldingValuationIssue({
    required this.assetId,
    required this.currency,
    required this.cause,
  });

  final String assetId;
  final String currency;
  final HoldingValuationIssueCause cause;
}

class HoldingSample {
  const HoldingSample({
    required this.asOf,
    required this.snapshots,
    this.issues = const [],
  });

  final DateTime asOf;
  final Map<String, HoldingSnapshot> snapshots;
  final List<HoldingValuationIssue> issues;
}

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

/// Optional optimized capability implemented by the production ledger
/// service. Keeping it separate avoids forcing lightweight service fakes to
/// understand chart sampling.
abstract interface class SampledHoldingService implements HoldingService {
  Future<List<HoldingSample>> computeAtSamples(Iterable<DateTime> dates);
}

extension HoldingServiceSampling on HoldingService {
  /// Holdings for a set of sample instants. The ledger service replays once;
  /// other implementations retain correct semantics via point reads.
  Future<List<HoldingSample>> computeAtSamples(Iterable<DateTime> dates) async {
    final service = this;
    if (service is SampledHoldingService) {
      return service.computeAtSamples(dates);
    }
    final sorted = dates.map((date) => date.toUtc()).toSet().toList()..sort();
    return [
      for (final date in sorted)
        HoldingSample(asOf: date, snapshots: await computeAt(date)),
    ];
  }
}
