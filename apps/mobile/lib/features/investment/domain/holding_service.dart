import '../../../data/domain/transaction.dart';
import '../../../domain/services/currency_converter.dart';
import 'cost_basis/cost_basis_method.dart';
import 'cost_basis_engine.dart';
import 'holding_computer.dart';
import 'holding_price_source.dart';
import 'models/corporate_actions.dart';
import 'models/holding_snapshot.dart';
import 'models/lot.dart';

/// Loads transactions + corporate actions for replay. Repositories are
/// expected to filter by `ownerUserId`, drop tombstoned rows, and return
/// records in any order (the computer sorts).
abstract class HoldingTransactionsRepository {
  /// Transactions with `tradeDate` in `[from, to]` (UTC, inclusive).
  Future<List<Transaction>> transactionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  });

  /// Corporate actions with `effectiveDate` in `[from, to]` (UTC, inclusive).
  /// Implementations that don't yet model corporate actions can return an
  /// empty list — splits will then have to be supplied directly to
  /// [HoldingComputer.replay] through a different code path.
  Future<List<CorporateAction>> corporateActionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  });
}

/// Storage for the daily lot-inventory snapshot cache. Implementations may
/// be in-memory (tests / first-render warm path) or Drift-backed (persisted
/// across launches).
abstract class HoldingDailySnapshotStore {
  /// Most recent snapshot whose `day` is `<= upTo` (UTC calendar day),
  /// or null if no snapshot exists in that range.
  Future<LotInventorySnapshot?> latestOnOrBefore({
    required String ownerUserId,
    required DateTime upTo,
  });

  /// Persist [snapshot]. Must be idempotent for the same `(ownerUserId, day)`
  /// — overwriting a stale snapshot is the expected behaviour after a
  /// historical transaction is back-dated and the day's snapshot needs to
  /// be re-materialized.
  Future<void> save(LotInventorySnapshot snapshot);

  /// Drop every snapshot at or after [from] for [ownerUserId]. Used when a
  /// back-dated transaction invalidates the chain — the next [computeAt]
  /// call will replay from the previous remaining snapshot forward.
  Future<void> invalidateFrom({
    required String ownerUserId,
    required DateTime from,
  });
}

/// Public contract: derive a per-asset [HoldingSnapshot] view of the user's
/// portfolio at a given moment.
///
/// Implementations are responsible for:
///
/// 1. Walking back to the most recent cached snapshot ([HoldingDailySnapshotStore]).
/// 2. Replaying the gap of transactions + corporate actions through
///    [HoldingComputer.replay].
/// 3. Pricing the resulting lots and converting to base currency via
///    [HoldingComputer.snapshot].
///
/// The interface is intentionally small — analytics / FIRE / XIRR / AI
/// assistant features all read holdings through this single seam, so it
/// stays stable as the implementation evolves.
abstract class HoldingService {
  /// Holdings as of [asOf]. Time-of-day matters: an `asOf` of
  /// `2026-04-28T12:00:00Z` excludes any transaction with `tradeDate >
  /// 12:00`, so intraday "current" computations should pass `DateTime.now()`
  /// (or its UTC equivalent) — the replay handles same-day deltas exactly
  /// as long as `tradeDate` is strictly less than `asOf`.
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf);

  /// Lot inventory at [asOf]. Same replay pipeline as [computeAt] but
  /// stops one step earlier — returns the raw [Lot]s without pricing them.
  /// FIR-89's [ReturnsService] consumes this for XIRR bookend valuation.
  Future<List<Lot>> lotsAt(DateTime asOf);

  /// Materialize and persist the lot inventory at end of [day].
  ///
  /// Intended to be called once per UTC trading day after market close (the
  /// "每日收盘后落档" step). Subsequent [computeAt] calls then replay only
  /// intraday deltas against the snapshot rather than the full transaction
  /// history. Idempotent.
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day);

  /// Drop every cached snapshot at or after [from]. Call after any
  /// back-dated edit to the transaction log so the next read recomputes
  /// from the next-older surviving snapshot.
  Future<void> invalidateFrom(DateTime from);
}

/// Default [HoldingService] implementation — composes a transactions
/// repository, snapshot store, price source and currency converter into a
/// concrete pipeline.
///
/// The implementation is deliberately storage-agnostic: it depends on the
/// abstract [HoldingDailySnapshotStore] and [HoldingTransactionsRepository]
/// rather than Drift directly, so the same code drives in-memory tests,
/// first-launch (empty cache) and the persisted production path.
class DefaultHoldingService implements HoldingService {
  DefaultHoldingService({
    required this.ownerUserId,
    required this.baseCurrency,
    required CostBasisMethod costBasisMethod,
    required this.transactions,
    required this.snapshots,
    required this.prices,
    required this.converter,
    String Function()? idGenerator,
    HoldingComputer? computer,
  }) : _computer =
           computer ??
           HoldingComputer(
             engine: CostBasisEngine.forMethod(
               costBasisMethod,
               idGenerator: idGenerator,
             ),
           );

  final String ownerUserId;
  final String baseCurrency;
  final HoldingTransactionsRepository transactions;
  final HoldingDailySnapshotStore snapshots;
  final HoldingPriceSource prices;
  final CurrencyConverter converter;

  final HoldingComputer _computer;

  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async {
    final lots = await _replayUpTo(asOf);
    return _computer.snapshot(
      lots: lots,
      asOf: asOf,
      prices: prices,
      converter: converter,
      baseCurrency: baseCurrency,
    );
  }

  @override
  Future<List<Lot>> lotsAt(DateTime asOf) => _replayUpTo(asOf);

  @override
  Future<LotInventorySnapshot> persistDailySnapshot(DateTime day) async {
    final boundary = _endOfDay(day);
    final lots = await _replayUpTo(boundary);
    final snapshot = LotInventorySnapshot(
      ownerUserId: ownerUserId,
      day: _utcDay(day),
      lots: lots,
    );
    await snapshots.save(snapshot);
    return snapshot;
  }

  @override
  Future<void> invalidateFrom(DateTime from) =>
      snapshots.invalidateFrom(ownerUserId: ownerUserId, from: _utcDay(from));

  /// Walk back to the most recent snapshot, then replay the gap through to
  /// [asOf]. Keeps the snapshot store as the single source of speedup —
  /// when no snapshot exists we fall back to a full-history replay starting
  /// from epoch.
  Future<List<Lot>> _replayUpTo(DateTime asOf) async {
    final snapshotCutoff = _utcDay(asOf).subtract(const Duration(days: 1));
    final cached = await snapshots.latestOnOrBefore(
      ownerUserId: ownerUserId,
      upTo: snapshotCutoff,
    );

    final initialLots = cached?.lots ?? const <Lot>[];
    // Replay starts the day *after* the cached snapshot's day; if no
    // snapshot exists, replay from a far-past sentinel — practical mobile
    // history won't reach back to year 0.
    final from = cached == null
        ? DateTime.utc(1900)
        : cached.day.add(const Duration(days: 1));

    final txns = await transactions.transactionsInRange(
      ownerUserId: ownerUserId,
      from: from,
      to: asOf,
    );
    final actions = await transactions.corporateActionsInRange(
      ownerUserId: ownerUserId,
      from: from,
      to: asOf,
    );

    final result = _computer.replay(
      initialLots: initialLots,
      transactions: txns,
      corporateActions: actions,
    );
    return result.lots;
  }

  static DateTime _utcDay(DateTime d) {
    final u = d.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }

  static DateTime _endOfDay(DateTime d) {
    final day = _utcDay(d);
    return day
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
  }
}

/// In-memory [HoldingDailySnapshotStore]. Suitable for tests and as a
/// first-launch warm cache before the Drift-backed implementation lands.
class InMemoryHoldingDailySnapshotStore implements HoldingDailySnapshotStore {
  final Map<String, List<LotInventorySnapshot>> _byOwner = {};

  @override
  Future<LotInventorySnapshot?> latestOnOrBefore({
    required String ownerUserId,
    required DateTime upTo,
  }) async {
    final list = _byOwner[ownerUserId];
    if (list == null || list.isEmpty) return null;
    final cutoff = _utcDay(upTo);
    LotInventorySnapshot? best;
    for (final snap in list) {
      if (snap.day.isAfter(cutoff)) continue;
      if (best == null || snap.day.isAfter(best.day)) best = snap;
    }
    return best;
  }

  @override
  Future<void> save(LotInventorySnapshot snapshot) async {
    final list = _byOwner.putIfAbsent(snapshot.ownerUserId, () => []);
    list.removeWhere((s) => s.day == snapshot.day);
    list.add(snapshot);
    list.sort((a, b) => a.day.compareTo(b.day));
  }

  @override
  Future<void> invalidateFrom({
    required String ownerUserId,
    required DateTime from,
  }) async {
    final list = _byOwner[ownerUserId];
    if (list == null) return;
    final cutoff = _utcDay(from);
    list.removeWhere((s) => !s.day.isBefore(cutoff));
  }

  static DateTime _utcDay(DateTime d) {
    final u = d.toUtc();
    return DateTime.utc(u.year, u.month, u.day);
  }
}

/// In-memory [HoldingTransactionsRepository] backed by flat lists.
class InMemoryHoldingTransactionsRepository
    implements HoldingTransactionsRepository {
  InMemoryHoldingTransactionsRepository({
    List<Transaction> transactions = const [],
    List<CorporateAction> corporateActions = const [],
  }) : _txns = List<Transaction>.from(transactions),
       _actions = List<CorporateAction>.from(corporateActions);

  final List<Transaction> _txns;
  final List<CorporateAction> _actions;

  /// Append [tx] to the in-memory log. Used by tests to incrementally build
  /// up history without re-instantiating the repository.
  void addTransaction(Transaction tx) => _txns.add(tx);

  /// Append [action] to the in-memory log.
  void addCorporateAction(CorporateAction action) => _actions.add(action);

  @override
  Future<List<Transaction>> transactionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) async {
    return _txns
        .where(
          (t) =>
              t.sync.ownerUserId == ownerUserId &&
              t.sync.deletedAt == null &&
              !t.tradeDate.isBefore(from) &&
              !t.tradeDate.isAfter(to),
        )
        .toList();
  }

  @override
  Future<List<CorporateAction>> corporateActionsInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) async {
    // Corporate actions don't yet have an owner partition in the model — the
    // service layer relies on the caller to scope them. For the in-memory
    // shim we simply filter on date.
    return _actions
        .where(
          (a) =>
              !a.effectiveDate.isBefore(from) && !a.effectiveDate.isAfter(to),
        )
        .toList();
  }
}
