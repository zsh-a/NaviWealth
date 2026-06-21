import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/domain/amortization_entry.dart';
import 'package:naviwealth/features/finance/data/domain/enums.dart';
import 'package:naviwealth/features/finance/data/domain/liability.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/app_database.dart';
import '../../../core/sync/op_outbox.dart';
import '../domain/amortization_calculator.dart';

/// Persistence + amortization-orchestration layer for liabilities.
///
/// Owns three tables together because they're inseparable from a user's
/// POV: the [Liability] header, its [AmortizationEntry] schedule rows, and
/// the journal entries that mark scheduled rows paid.
///
/// Mutation contract matches `AccountRepository` / `ManualAssetRepository`:
/// every write happens inside a Drift transaction that *both* persists the
/// row and marks it dirty in the sync outbox. The schedule-generation pass
/// at create time queues one liability row and one amortization-entry row
/// per period in the same transaction.
class LiabilityRepository {
  LiabilityRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    required JournalEntryRepository journalEntryRepo,
    AmortizationCalculator? calculator,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _journalEntryRepo = journalEntryRepo,
       _calc = calculator ?? AmortizationCalculator(),
       _uuid = uuid,
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final JournalEntryRepository _journalEntryRepo;
  final AmortizationCalculator _calc;
  final Uuid _uuid;
  final DateTime Function() _clock;

  static const String _liabilityTable = 'liabilities';
  static const String _amortTable = 'amortization_entries';

  // ---------- Reads ----------

  /// Live list of all liabilities for the active user, excluding tombstones.
  /// Sorted by `name` for stable list order regardless of insertion order;
  /// the UI is the right place to apply user-selected sort.
  Stream<List<Liability>> watchAll() {
    final q = _db.select(_db.liabilities)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch().map((rows) => rows.map(_toLiability).toList());
  }

  /// One-shot read of a single liability by id. Returns null if missing or
  /// tombstoned, so the UI can show a "not found" state without throwing.
  Future<Liability?> findById(String id) async {
    final row = await (_db.select(
      _db.liabilities,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row == null ? null : _toLiability(row);
  }

  /// Live amortization schedule for one liability, ordered by period.
  /// Empty for revolving credit (no schedule generated at create).
  Stream<List<AmortizationEntry>> watchSchedule(String liabilityId) {
    final q = _db.select(_db.amortizationEntries)
      ..where((t) => t.liabilityId.equals(liabilityId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.periodIndex)]);
    return q.watch().map((rows) => rows.map(_toAmort).toList());
  }

  Future<List<AmortizationEntry>> scheduleFor(String liabilityId) async {
    final rows =
        await (_db.select(_db.amortizationEntries)
              ..where(
                (t) => t.liabilityId.equals(liabilityId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.periodIndex)]))
            .get();
    return rows.map(_toAmort).toList();
  }

  // ---------- Writes ----------

  /// Insert a liability and synthesize its full amortization schedule in
  /// one transaction. Returns the created [Liability]; callers can re-read
  /// the schedule via [scheduleFor] when they need it.
  ///
  /// Schedule generation is skipped when [Liability.termMonths] /
  /// [Liability.startDate] is null — credit-card and revolving lines don't
  /// have a fixed schedule. Those rows still count toward net worth but
  /// don't get amortization rows.
  Future<Liability> create({
    required LiabilityType type,
    required String name,
    required Decimal principal,
    required Decimal interestRate,
    required String currency,
    RepaymentMethod paymentMethod = RepaymentMethod.equalInstallment,
    LiabilityRateType rateType = LiabilityRateType.fixed,
    String? accountId,
    DateTime? startDate,
    DateTime? endDate,
    int? termMonths,
    Decimal? monthlyPayment,
    int? statementDay,
    int? paymentDueDay,
    String? note,
  }) async {
    final stamp = await _stamper.stamp();
    final id = _uuid.v4();

    final companion = LiabilitiesCompanion.insert(
      id: id,
      type: type,
      name: name,
      principal: principal,
      interestRate: interestRate,
      currency: currency,
      paymentMethod: Value(paymentMethod),
      rateType: Value(rateType),
      accountId: Value(accountId),
      startDate: Value(startDate),
      endDate: Value(endDate),
      termMonths: Value(termMonths),
      monthlyPayment: Value(monthlyPayment),
      statementDay: Value(statementDay),
      paymentDueDay: Value(paymentDueDay),
      note: Value(note),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );

    final scheduleRows = _buildSchedule(
      liabilityId: id,
      principal: principal,
      interestRate: interestRate,
      termMonths: termMonths,
      startDate: startDate,
      method: paymentMethod,
    );

    await _db.transaction(() async {
      await _db.into(_db.liabilities).insert(companion);
      await _outbox.enqueue(table: _liabilityTable, rowId: id);

      for (final entry in scheduleRows) {
        await _db
            .into(_db.amortizationEntries)
            .insert(_amortizationCompanion(entry, stamp));
        await _outbox.enqueue(table: _amortTable, rowId: entry.id);
      }
    });

    return (await findById(id))!;
  }

  /// Update metadata that does not affect the amortization schedule.
  ///
  /// Principal, rate, term, start date and repayment method are deliberately
  /// excluded; changing them requires schedule regeneration semantics.
  Future<Liability> updateMetadata({
    required String id,
    required String name,
    String? note,
  }) async {
    final stamp = await _stamper.stamp();
    final changed =
        await (_db.update(
          _db.liabilities,
        )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
          LiabilitiesCompanion(
            name: Value(name),
            note: Value(note),
            updatedAt: Value(stamp.now),
            updatedByDevice: Value(stamp.deviceId),
            hlc: Value(stamp.hlc),
          ),
        );
    if (changed == 0) {
      throw StateError('Liability $id not found');
    }
    await _outbox.enqueue(table: _liabilityTable, rowId: id);
    return (await findById(id))!;
  }

  /// Mark a single amortization period paid and emit the matching journal
  /// entry.
  ///
  /// [paidAt] defaults to "now" but is parameterized so historical entries
  /// (catching up after vacation) record the correct date for reporting.
  /// Returns the journal entry id when a journal entry is produced, otherwise
  /// the amortization entry id.
  Future<String> registerPayment({
    required String liabilityId,
    required int periodIndex,
    DateTime? paidAt,
  }) async {
    final liability = await findById(liabilityId);
    if (liability == null) {
      throw StateError('Liability $liabilityId not found');
    }
    final entry =
        await (_db.select(_db.amortizationEntries)..where(
              (t) =>
                  t.liabilityId.equals(liabilityId) &
                  t.periodIndex.equals(periodIndex) &
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
    final stamp = await _stamper.stamp();
    String? journalEntryId;

    await _db.transaction(() async {
      await (_db.update(
        _db.amortizationEntries,
      )..where((t) => t.id.equals(entry.id))).write(
        AmortizationEntriesCompanion(
          paidAt: Value(whenPaid),
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
        ),
      );
      await _outbox.enqueue(table: _amortTable, rowId: entry.id);

      final liabilityAccountId = AccountRepository.systemAccountIdForPath(
        'liability:${liability.id}',
        ownerUserId: stamp.ownerUserId,
      );
      final interestExpenseAccountId = AccountRepository.systemAccountIdForPath(
        'expense:trading:interest',
        ownerUserId: stamp.ownerUserId,
      );
      final build = JournalEntryBuilders.liabilityPayment(
        date: whenPaid,
        liabilityAccountId: liabilityAccountId,
        fromAccountId: accountId,
        interestExpenseAccountId: interestExpenseAccountId,
        principal: entry.principalPayment,
        interest: entry.interestPayment,
        currency: liability.currency,
        narration: 'Liability ${liability.name} · period $periodIndex',
      );
      final stored = await _journalEntryRepo.create(
        entry: build.entry,
        postings: build.postings,
      );
      journalEntryId = stored.entry.id;
    });

    return journalEntryId!;
  }

  // ---------- Internals ----------

  List<AmortizationEntry> _buildSchedule({
    required String liabilityId,
    required Decimal principal,
    required Decimal interestRate,
    required int? termMonths,
    required DateTime? startDate,
    required RepaymentMethod method,
  }) {
    if (termMonths == null || startDate == null) return const [];
    final rows = _calc.generate(
      principal: principal,
      annualInterestRate: interestRate,
      termMonths: termMonths,
      startDate: startDate,
      method: method,
    );
    return [
      for (final r in rows)
        AmortizationEntry(
          id: _uuid.v4(),
          liabilityId: liabilityId,
          periodIndex: r.periodIndex,
          dueDate: r.dueDate,
          principalPayment: r.principalPayment,
          interestPayment: r.interestPayment,
          remainingBalance: r.remainingBalance,
          // Sync metadata is filled in by the writer using the active
          // [MutationStamp]; the in-memory placeholder here is never
          // persisted because [_amortizationCompanion] reads from the
          // stamp, not from this struct.
          sync: SyncMeta(
            ownerUserId: '',
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
            updatedByDevice: '',
            hlc: Hlc.zero('placeholder'),
          ),
        ),
    ];
  }

  AmortizationEntriesCompanion _amortizationCompanion(
    AmortizationEntry e,
    MutationStamp stamp,
  ) {
    return AmortizationEntriesCompanion.insert(
      id: e.id,
      liabilityId: e.liabilityId,
      periodIndex: e.periodIndex,
      dueDate: e.dueDate,
      principalPayment: e.principalPayment,
      interestPayment: e.interestPayment,
      remainingBalance: e.remainingBalance,
      paidAt: Value(e.paidAt),
      ownerUserId: stamp.ownerUserId,
      updatedAt: stamp.now,
      updatedByDevice: stamp.deviceId,
      hlc: stamp.hlc,
    );
  }

  Liability _toLiability(LiabilityRow r) {
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

  AmortizationEntry _toAmort(AmortizationEntryRow r) {
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
