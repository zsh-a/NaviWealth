import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../../data/db/app_database.dart';
import '../../../data/domain/amortization_entry.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/hlc.dart';
import '../../../data/domain/liability.dart';
import '../../../data/domain/sync_meta.dart';
import '../domain/amortization_calculator.dart';

/// Wall-clock + HLC source for repository writes. Production wires this to
/// `SyncEngine.stampHlc`; tests pass a deterministic fake.
typedef HlcStamp = Future<Hlc> Function();

/// Persistence + amortization-orchestration layer for liabilities.
///
/// The repository owns three things together because they're inseparable
/// from a user's POV: the [Liability] header, its [AmortizationEntry]
/// schedule rows, and the [TransactionType.liabilityPayment] cash-flow
/// records that mark scheduled rows paid. Splitting them across three
/// repositories would force the UI to coordinate transactions across them,
/// which is exactly the bug surface this layer exists to prevent.
class LiabilityRepository {
  LiabilityRepository({
    required this.db,
    required this.ownerUserId,
    required this.deviceId,
    required this.stampHlc,
    AmortizationCalculator? calculator,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) : _calc = calculator ?? AmortizationCalculator(),
       _id = idGenerator ?? _defaultIdGenerator,
       _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final String ownerUserId;
  final String deviceId;
  final HlcStamp stampHlc;
  final AmortizationCalculator _calc;
  final String Function() _id;
  final DateTime Function() _clock;

  static const Uuid _uuid = Uuid();
  static String _defaultIdGenerator() => _uuid.v4();

  /// Insert a liability and synthesize its full amortization schedule in
  /// one transaction. Returns the created [Liability]; callers can re-read
  /// the schedule via [scheduleFor] when they need it.
  ///
  /// Schedule generation is skipped when [Liability.termMonths] /
  /// [Liability.startDate] is null — credit-card and revolving lines don't
  /// have a fixed schedule. Those rows still count toward net worth but
  /// don't get amortization rows.
  Future<Liability> create(Liability liability) async {
    final hlc = await stampHlc();
    final now = _clock();
    final stamped = liability.copyWith(
      sync: SyncMeta(
        ownerUserId: ownerUserId,
        updatedAt: now,
        updatedByDevice: deviceId,
        hlc: hlc,
      ),
    );

    await db.transaction(() async {
      await db.into(db.liabilities).insert(_toLiabilityRow(stamped));
      final schedule = _buildSchedule(stamped);
      if (schedule.isNotEmpty) {
        await db.batch((b) {
          b.insertAll(
            db.amortizationEntries,
            schedule.map(_toAmortizationRow).toList(),
          );
        });
      }
    });

    return stamped;
  }

  /// Live list of all liabilities for [ownerUserId], excluding tombstones.
  /// Sorted by `name` for stable list order regardless of insertion order;
  /// the UI is the right place to apply user-selected sort.
  Stream<List<Liability>> watchAll() {
    final q = db.select(db.liabilities)
      ..where((t) => t.ownerUserId.equals(ownerUserId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch().map((rows) => rows.map(_fromLiabilityRow).toList());
  }

  /// One-shot read of a single liability by id. Returns null if missing or
  /// tombstoned, so the UI can show a "not found" state without throwing.
  Future<Liability?> getById(String id) async {
    final row =
        await (db.select(db.liabilities)
              ..where(
                (t) =>
                    t.id.equals(id) &
                    t.ownerUserId.equals(ownerUserId) &
                    t.deletedAt.isNull(),
              ))
            .getSingleOrNull();
    return row == null ? null : _fromLiabilityRow(row);
  }

  /// Live amortization schedule for one liability, ordered by period.
  /// Empty for revolving credit (no schedule generated at create).
  Stream<List<AmortizationEntry>> watchSchedule(String liabilityId) {
    final q = db.select(db.amortizationEntries)
      ..where(
        (t) =>
            t.liabilityId.equals(liabilityId) &
            t.ownerUserId.equals(ownerUserId) &
            t.deletedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.periodIndex)]);
    return q.watch().map((rows) => rows.map(_fromAmortizationRow).toList());
  }

  Future<List<AmortizationEntry>> scheduleFor(String liabilityId) async {
    final rows =
        await (db.select(db.amortizationEntries)
              ..where(
                (t) =>
                    t.liabilityId.equals(liabilityId) &
                    t.ownerUserId.equals(ownerUserId) &
                    t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.periodIndex)]))
            .get();
    return rows.map(_fromAmortizationRow).toList();
  }

  /// Mark a single amortization period paid and emit the matching
  /// `liabilityPayment` transaction. The two writes happen in one DB
  /// transaction so a crash between them never leaves the schedule out of
  /// sync with the cash-flow ledger.
  ///
  /// [paidAt] defaults to "now" but is parameterized so historical entries
  /// (catching up after vacation) record the correct date for reporting.
  /// Returns the transaction id so callers can navigate / undo.
  Future<String> registerPayment({
    required String liabilityId,
    required int periodIndex,
    DateTime? paidAt,
  }) async {
    final liability = await getById(liabilityId);
    if (liability == null) {
      throw StateError('Liability $liabilityId not found');
    }
    final entry =
        await (db.select(db.amortizationEntries)
              ..where(
                (t) =>
                    t.liabilityId.equals(liabilityId) &
                    t.periodIndex.equals(periodIndex) &
                    t.ownerUserId.equals(ownerUserId) &
                    t.deletedAt.isNull(),
              ))
            .getSingleOrNull();
    if (entry == null) {
      throw StateError(
        'Amortization period $periodIndex not found for $liabilityId',
      );
    }
    if (entry.paidAt != null) {
      throw StateError(
        'Period $periodIndex of $liabilityId is already marked paid',
      );
    }

    final accountId = liability.accountId;
    if (accountId == null) {
      throw StateError(
        'Liability $liabilityId has no payer account; assign one before '
        'registering a payment',
      );
    }

    final whenPaid = paidAt ?? _clock();
    final amortHlc = await stampHlc();
    final txHlc = await stampHlc();
    final txId = _id();
    final totalPayment = entry.principalPayment + entry.interestPayment;

    await db.transaction(() async {
      await (db.update(db.amortizationEntries)
            ..where((t) => t.id.equals(entry.id)))
          .write(
            AmortizationEntriesCompanion(
              paidAt: Value(whenPaid),
              updatedAt: Value(_clock()),
              updatedByDevice: Value(deviceId),
              hlc: Value(amortHlc),
            ),
          );

      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: txId,
              accountId: accountId,
              type: TransactionType.liabilityPayment,
              quantity: Decimal.one,
              price: totalPayment,
              currency: liability.currency,
              tradeDate: whenPaid,
              note: Value(
                'Liability ${liability.name} · period $periodIndex',
              ),
              ownerUserId: ownerUserId,
              updatedAt: _clock(),
              updatedByDevice: deviceId,
              hlc: txHlc,
            ),
          );
    });

    return txId;
  }

  // -- internals --------------------------------------------------------

  List<AmortizationEntry> _buildSchedule(Liability liability) {
    final term = liability.termMonths;
    final start = liability.startDate;
    if (term == null || start == null) return const [];
    final rows = _calc.generate(
      principal: liability.principal,
      annualInterestRate: liability.interestRate,
      termMonths: term,
      startDate: start,
      method: liability.paymentMethod,
    );
    final hlc = liability.sync.hlc;
    return rows.map((r) {
      return AmortizationEntry(
        id: _id(),
        liabilityId: liability.id,
        periodIndex: r.periodIndex,
        dueDate: r.dueDate,
        principalPayment: r.principalPayment,
        interestPayment: r.interestPayment,
        remainingBalance: r.remainingBalance,
        sync: SyncMeta(
          ownerUserId: ownerUserId,
          updatedAt: liability.sync.updatedAt,
          updatedByDevice: deviceId,
          hlc: hlc,
        ),
      );
    }).toList();
  }

  LiabilitiesCompanion _toLiabilityRow(Liability l) {
    return LiabilitiesCompanion.insert(
      id: l.id,
      type: l.type,
      name: l.name,
      principal: l.principal,
      interestRate: l.interestRate,
      currency: l.currency,
      paymentMethod: Value(l.paymentMethod),
      rateType: Value(l.rateType),
      accountId: Value(l.accountId),
      startDate: Value(l.startDate),
      endDate: Value(l.endDate),
      termMonths: Value(l.termMonths),
      monthlyPayment: Value(l.monthlyPayment),
      statementDay: Value(l.statementDay),
      paymentDueDay: Value(l.paymentDueDay),
      note: Value(l.note),
      ownerUserId: l.sync.ownerUserId,
      updatedAt: l.sync.updatedAt,
      updatedByDevice: l.sync.updatedByDevice,
      hlc: l.sync.hlc,
      deletedAt: Value(l.sync.deletedAt),
    );
  }

  Liability _fromLiabilityRow(LiabilityRow r) {
    return Liability(
      id: r.id,
      type: r.type,
      name: r.name,
      principal: r.principal,
      interestRate: r.interestRate,
      currency: r.currency,
      paymentMethod: r.paymentMethod,
      rateType: r.rateType,
      accountId: r.accountId,
      startDate: r.startDate,
      endDate: r.endDate,
      termMonths: r.termMonths,
      monthlyPayment: r.monthlyPayment,
      statementDay: r.statementDay,
      paymentDueDay: r.paymentDueDay,
      note: r.note,
      sync: SyncMeta(
        ownerUserId: r.ownerUserId,
        updatedAt: r.updatedAt,
        updatedByDevice: r.updatedByDevice,
        hlc: r.hlc,
        deletedAt: r.deletedAt,
      ),
    );
  }

  AmortizationEntriesCompanion _toAmortizationRow(AmortizationEntry e) {
    return AmortizationEntriesCompanion.insert(
      id: e.id,
      liabilityId: e.liabilityId,
      periodIndex: e.periodIndex,
      dueDate: e.dueDate,
      principalPayment: e.principalPayment,
      interestPayment: e.interestPayment,
      remainingBalance: e.remainingBalance,
      paidAt: Value(e.paidAt),
      ownerUserId: e.sync.ownerUserId,
      updatedAt: e.sync.updatedAt,
      updatedByDevice: e.sync.updatedByDevice,
      hlc: e.sync.hlc,
      deletedAt: Value(e.sync.deletedAt),
    );
  }

  AmortizationEntry _fromAmortizationRow(AmortizationEntryRow r) {
    return AmortizationEntry(
      id: r.id,
      liabilityId: r.liabilityId,
      periodIndex: r.periodIndex,
      dueDate: r.dueDate,
      principalPayment: r.principalPayment,
      interestPayment: r.interestPayment,
      remainingBalance: r.remainingBalance,
      paidAt: r.paidAt,
      sync: SyncMeta(
        ownerUserId: r.ownerUserId,
        updatedAt: r.updatedAt,
        updatedByDevice: r.updatedByDevice,
        hlc: r.hlc,
        deletedAt: r.deletedAt,
      ),
    );
  }
}
