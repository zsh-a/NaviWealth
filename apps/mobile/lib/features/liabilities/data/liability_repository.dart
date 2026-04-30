import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import '../../../core/sync/op.dart';
import '../../../core/sync/op_outbox.dart';
import '../../../data/db/app_database.dart';
import '../../../data/domain/amortization_entry.dart';
import '../../../data/domain/enums.dart';
import '../../../data/domain/hlc.dart';
import '../../../data/domain/liability.dart';
import '../../../data/domain/sync_meta.dart';
import '../../../data/repositories/mutation_context.dart';
import '../domain/amortization_calculator.dart';

/// Persistence + amortization-orchestration layer for liabilities.
///
/// Owns three tables together because they're inseparable from a user's
/// POV: the [Liability] header, its [AmortizationEntry] schedule rows, and
/// the [TransactionType.liabilityPayment] cash-flow records that mark
/// scheduled rows paid. Splitting them across three repositories would
/// force the UI to coordinate transactions across them, which is exactly
/// the bug surface this layer exists to prevent.
///
/// Mutation contract matches `AccountRepository` / `ManualAssetRepository`:
/// every write happens inside a Drift transaction that *both* persists the
/// row and enqueues the matching [Op] into the sync outbox. The
/// schedule-generation pass at create time queues one liability insert and
/// one amortization-entry insert per period in the same transaction.
class LiabilityRepository {
  LiabilityRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    AmortizationCalculator? calculator,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _calc = calculator ?? AmortizationCalculator(),
       _uuid = uuid,
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final AmortizationCalculator _calc;
  final Uuid _uuid;
  final DateTime Function() _clock;

  static const String _liabilityTable = 'liabilities';
  static const String _amortTable = 'amortization_entries';
  static const String _txTable = 'transactions';

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
    final row =
        await (_db.select(_db.liabilities)
              ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
            .getSingleOrNull();
    return row == null ? null : _toLiability(row);
  }

  /// Live amortization schedule for one liability, ordered by period.
  /// Empty for revolving credit (no schedule generated at create).
  Stream<List<AmortizationEntry>> watchSchedule(String liabilityId) {
    final q = _db.select(_db.amortizationEntries)
      ..where(
        (t) => t.liabilityId.equals(liabilityId) & t.deletedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.periodIndex)]);
    return q.watch().map((rows) => rows.map(_toAmort).toList());
  }

  Future<List<AmortizationEntry>> scheduleFor(String liabilityId) async {
    final rows =
        await (_db.select(_db.amortizationEntries)
              ..where(
                (t) =>
                    t.liabilityId.equals(liabilityId) & t.deletedAt.isNull(),
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
      await _enqueue(
        table: _liabilityTable,
        opType: OpType.insert,
        rowId: id,
        fields: _liabilityInsertFields(
          id: id,
          type: type,
          name: name,
          principal: principal,
          interestRate: interestRate,
          currency: currency,
          paymentMethod: paymentMethod,
          rateType: rateType,
          accountId: accountId,
          startDate: startDate,
          endDate: endDate,
          termMonths: termMonths,
          monthlyPayment: monthlyPayment,
          statementDay: statementDay,
          paymentDueDay: paymentDueDay,
          note: note,
          stamp: stamp,
        ),
        stamp: stamp,
      );

      for (final entry in scheduleRows) {
        await _db
            .into(_db.amortizationEntries)
            .insert(_amortizationCompanion(entry, stamp));
        await _enqueue(
          table: _amortTable,
          opType: OpType.insert,
          rowId: entry.id,
          fields: _amortInsertFields(entry, stamp),
          stamp: stamp,
        );
      }
    });

    return (await findById(id))!;
  }

  /// Mark a single amortization period paid and emit the matching
  /// `liabilityPayment` transaction. The two writes (plus the matching
  /// `update` and `insert` outbox ops) commit together so a crash never
  /// leaves the schedule out of sync with the cash-flow ledger.
  ///
  /// [paidAt] defaults to "now" but is parameterized so historical entries
  /// (catching up after vacation) record the correct date for reporting.
  /// Returns the transaction id so callers can navigate / undo.
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
        await (_db.select(_db.amortizationEntries)
              ..where(
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
    final txId = _uuid.v4();
    final totalPayment = entry.principalPayment + entry.interestPayment;

    await _db.transaction(() async {
      await (_db.update(_db.amortizationEntries)
            ..where((t) => t.id.equals(entry.id)))
          .write(
            AmortizationEntriesCompanion(
              paidAt: Value(whenPaid),
              updatedAt: Value(stamp.now),
              updatedByDevice: Value(stamp.deviceId),
              hlc: Value(stamp.hlc),
            ),
          );
      await _enqueue(
        table: _amortTable,
        opType: OpType.update,
        rowId: entry.id,
        fields: <String, Object?>{
          'paid_at': whenPaid.toUtc().toIso8601String(),
          'updated_at': stamp.now.toUtc().toIso8601String(),
          'updated_by_device': stamp.deviceId,
          'hlc': stamp.hlc.toString(),
        },
        stamp: stamp,
      );

      final txCompanion = TransactionsCompanion.insert(
        id: txId,
        accountId: accountId,
        type: TransactionType.liabilityPayment,
        quantity: Decimal.one,
        price: totalPayment,
        currency: liability.currency,
        tradeDate: whenPaid,
        note: Value('Liability ${liability.name} · period $periodIndex'),
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      );
      await _db.into(_db.transactions).insert(txCompanion);
      await _enqueue(
        table: _txTable,
        opType: OpType.insert,
        rowId: txId,
        fields: <String, Object?>{
          'id': txId,
          'account_id': accountId,
          'type': TransactionType.liabilityPayment.name,
          'quantity': Decimal.one.toString(),
          'price': totalPayment.toString(),
          'currency': liability.currency,
          'trade_date': whenPaid.toUtc().toIso8601String(),
          'note': 'Liability ${liability.name} · period $periodIndex',
          'owner_user_id': stamp.ownerUserId,
          'updated_at': stamp.now.toUtc().toIso8601String(),
          'updated_by_device': stamp.deviceId,
          'hlc': stamp.hlc.toString(),
        },
        stamp: stamp,
      );
    });

    return txId;
  }

  /// Ad-hoc liability payment without a schedule period (FIR-67 propose
  /// flow). Writes a `liabilityPayment` transaction tied to [liabilityId]
  /// from [fromAccountId] but does NOT mark any amortization period paid —
  /// the AI assistant can record a payment from natural language without
  /// the user picking a specific period, and revolving credit cards have no
  /// schedule to mark anyway.
  ///
  /// Returns the transaction id so the propose card can soft-delete it on
  /// undo via [TransactionRepository.softDeleteById].
  Future<String> recordAdhocPayment({
    required String liabilityId,
    required String fromAccountId,
    required Decimal amount,
    required String currency,
    DateTime? date,
    String? note,
  }) async {
    if (amount.sign <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Liability payment amount must be a positive magnitude.',
      );
    }
    final liability = await findById(liabilityId);
    if (liability == null) {
      throw StateError('Liability $liabilityId not found');
    }
    final whenPaid = date ?? _clock();
    final stamp = await _stamper.stamp();
    final txId = _uuid.v4();
    final composedNote = note ?? 'Liability ${liability.name} payment';

    await _db.transaction(() async {
      final companion = TransactionsCompanion.insert(
        id: txId,
        accountId: fromAccountId,
        type: TransactionType.liabilityPayment,
        quantity: Decimal.one,
        price: amount,
        currency: currency,
        tradeDate: whenPaid,
        note: Value(composedNote),
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      );
      await _db.into(_db.transactions).insert(companion);
      await _enqueue(
        table: _txTable,
        opType: OpType.insert,
        rowId: txId,
        fields: <String, Object?>{
          'id': txId,
          'account_id': fromAccountId,
          'type': TransactionType.liabilityPayment.name,
          'quantity': Decimal.one.toString(),
          'price': amount.toString(),
          'currency': currency,
          'trade_date': whenPaid.toUtc().toIso8601String(),
          'note': composedNote,
          'owner_user_id': stamp.ownerUserId,
          'updated_at': stamp.now.toUtc().toIso8601String(),
          'updated_by_device': stamp.deviceId,
          'hlc': stamp.hlc.toString(),
        },
        stamp: stamp,
      );
    });
    return txId;
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

  Map<String, Object?> _liabilityInsertFields({
    required String id,
    required LiabilityType type,
    required String name,
    required Decimal principal,
    required Decimal interestRate,
    required String currency,
    required RepaymentMethod paymentMethod,
    required LiabilityRateType rateType,
    required String? accountId,
    required DateTime? startDate,
    required DateTime? endDate,
    required int? termMonths,
    required Decimal? monthlyPayment,
    required int? statementDay,
    required int? paymentDueDay,
    required String? note,
    required MutationStamp stamp,
  }) {
    return <String, Object?>{
      'id': id,
      'type': type.name,
      'name': name,
      'principal': principal.toString(),
      'interest_rate': interestRate.toString(),
      'currency': currency,
      'payment_method': paymentMethod.name,
      'rate_type': rateType.name,
      'account_id': accountId,
      'start_date': startDate?.toUtc().toIso8601String(),
      'end_date': endDate?.toUtc().toIso8601String(),
      'term_months': termMonths,
      'monthly_payment': monthlyPayment?.toString(),
      'statement_day': statementDay,
      'payment_due_day': paymentDueDay,
      'note': note,
      'owner_user_id': stamp.ownerUserId,
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
  }

  Map<String, Object?> _amortInsertFields(
    AmortizationEntry e,
    MutationStamp stamp,
  ) {
    return <String, Object?>{
      'id': e.id,
      'liability_id': e.liabilityId,
      'period_index': e.periodIndex,
      'due_date': e.dueDate.toUtc().toIso8601String(),
      'principal_payment': e.principalPayment.toString(),
      'interest_payment': e.interestPayment.toString(),
      'remaining_balance': e.remainingBalance.toString(),
      'paid_at': e.paidAt?.toUtc().toIso8601String(),
      'owner_user_id': stamp.ownerUserId,
      'updated_at': stamp.now.toUtc().toIso8601String(),
      'updated_by_device': stamp.deviceId,
      'hlc': stamp.hlc.toString(),
    };
  }

  Future<void> _enqueue({
    required String table,
    required OpType opType,
    required String rowId,
    required Map<String, Object?>? fields,
    required MutationStamp stamp,
  }) async {
    final op = Op(
      opId: _uuid.v4(),
      tableName: table,
      rowId: rowId,
      opType: opType,
      fieldsDiff: fields,
      hlc: stamp.hlc,
      deviceId: stamp.deviceId,
    );
    await _outbox.enqueue(op);
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

