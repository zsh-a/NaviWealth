import '../models/lot.dart';
import 'trade_draft.dart';
import 'trade_entry_plan.dart';

/// Orchestration boundary for "the user is recording a security trade".
///
/// The service is responsible for:
///   - validating the [TradeDraft] (quantity sign / scale, fee non-negative,
///     etc.);
///   - backfilling the trade-day price from [MarketDataService] when the
///     user left it empty;
///   - converting the backfilled price across currencies when the asset's
///     quoted currency differs from the trade currency;
///   - delegating cost-basis bookkeeping to [CostBasisEngine] (new lot for
///     buys, lot consumption + realized P&L for sells);
///   - returning a self-contained [TradeEntryPlan] the persistence layer
///     can write straight through.
///
/// The service is **pure** in the sense that it does not touch the database
/// itself — that's the repository's job. This split lets us unit-test the
/// orchestration without spinning up Drift, and lets the persistence layer
/// stamp HLCs / write OpLog rows in a single transaction.
abstract class TradeEntryService {
  /// Resolve [draft] given the current [openLots] for the account / asset.
  /// Throws [TradeEntryException] for any validation error or unrecoverable
  /// market-data failure.
  Future<TradeEntryPlan> buildPlan(
    TradeDraft draft, {
    required List<Lot> openLots,
  });

}
