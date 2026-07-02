import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_builders.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:uuid/uuid.dart';

import '../domain/recurrence_engine.dart';
import '../domain/recurring_transaction.dart';

class RecurringTransactionRepository {
  RecurringTransactionRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final MutationStamper _stamper;
  final Uuid _uuid;

  static const String tableName = 'recurring_transactions';

  Stream<List<RecurringTransaction>> watchEnabled() {
    final query = _db.select(_db.recurringTransactions)
      ..where((t) => t.deletedAt.isNull())
      ..where((t) => t.enabled.equals(true))
      ..orderBy([(t) => OrderingTerm(expression: t.nextDueAt)]);
    return query.watch().map(
      (rows) => rows.map(_rowToDomain).toList(growable: false),
    );
  }

  Future<List<RecurringTransaction>> dueAt(DateTime now) async {
    final rows =
        await (_db.select(_db.recurringTransactions)
              ..where((t) => t.deletedAt.isNull())
              ..where((t) => t.enabled.equals(true))
              ..where((t) => t.nextDueAt.isSmallerOrEqualValue(now))
              ..orderBy([(t) => OrderingTerm(expression: t.nextDueAt)]))
            .get();
    return rows.map(_rowToDomain).toList(growable: false);
  }

  Future<RecurringTransaction?> getById(String id) async {
    final row =
        await (_db.select(_db.recurringTransactions)
              ..where((t) => t.id.equals(id))
              ..where((t) => t.deletedAt.isNull()))
            .getSingleOrNull();
    return row == null ? null : _rowToDomain(row);
  }

  Future<RecurringTransaction> create({
    String? id,
    required String templateJournalBuildJson,
    required String rrule,
    required DateTime nextDueAt,
    DateTime? lastMaterialisedAt,
    bool enabled = true,
  }) async {
    const RecurrenceEngine().parse(rrule);
    JournalBuildTemplateCodec.decode(templateJournalBuildJson);
    final stamp = await _stamper.stamp();
    final transaction = RecurringTransaction(
      id: id ?? _uuid.v4(),
      templateJournalBuildJson: templateJournalBuildJson,
      rrule: rrule,
      nextDueAt: _dateOnlyUtc(nextDueAt),
      lastMaterialisedAt: lastMaterialisedAt == null
          ? null
          : _dateOnlyUtc(lastMaterialisedAt),
      enabled: enabled,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _db.transaction(() async {
      await _db.into(_db.recurringTransactions).insert(_companion(transaction));
      await _outbox.enqueue(table: tableName, rowId: transaction.id);
    });
    return transaction;
  }

  Future<RecurringTransaction> update(
    String id, {
    String? templateJournalBuildJson,
    String? rrule,
    DateTime? nextDueAt,
    DateTime? lastMaterialisedAt,
    bool? enabled,
  }) async {
    if (rrule != null) const RecurrenceEngine().parse(rrule);
    if (templateJournalBuildJson != null) {
      JournalBuildTemplateCodec.decode(templateJournalBuildJson);
    }
    final existing = await getById(id);
    if (existing == null) {
      throw StateError('Unknown recurring transaction id=$id');
    }
    final stamp = await _stamper.stamp();
    final updated = existing.copyWith(
      templateJournalBuildJson: templateJournalBuildJson,
      rrule: rrule,
      nextDueAt: nextDueAt == null ? null : _dateOnlyUtc(nextDueAt),
      lastMaterialisedAt: lastMaterialisedAt == null
          ? existing.lastMaterialisedAt
          : _dateOnlyUtc(lastMaterialisedAt),
      enabled: enabled,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    );
    await _db.transaction(() async {
      await (_db.update(
        _db.recurringTransactions,
      )..where((t) => t.id.equals(id))).write(_updateCompanion(updated));
      await _outbox.enqueue(table: tableName, rowId: id);
    });
    return updated;
  }

  Future<RecurringTransaction> markMaterialised({
    required String id,
    required DateTime occurrenceDate,
    required DateTime nextDueAt,
  }) {
    return update(
      id,
      lastMaterialisedAt: _dateOnlyUtc(occurrenceDate),
      nextDueAt: _dateOnlyUtc(nextDueAt),
    );
  }

  Future<void> softDelete(String id) async {
    final stamp = await _stamper.stamp();
    await _db.transaction(() async {
      await (_db.update(
        _db.recurringTransactions,
      )..where((t) => t.id.equals(id))).write(
        RecurringTransactionsCompanion(
          updatedAt: Value(stamp.now),
          updatedByDevice: Value(stamp.deviceId),
          hlc: Value(stamp.hlc),
          deletedAt: Value(stamp.now),
        ),
      );
      await _outbox.enqueue(table: tableName, rowId: id);
    });
  }

  RecurringTransaction _rowToDomain(RecurringTransactionRow row) {
    return RecurringTransaction(
      id: row.id,
      templateJournalBuildJson: row.templateJournalBuildJson,
      rrule: row.rrule,
      nextDueAt: row.nextDueAt,
      lastMaterialisedAt: row.lastMaterialisedAt,
      enabled: row.enabled,
      sync: SyncMeta(
        ownerUserId: row.ownerUserId,
        updatedAt: row.updatedAt,
        updatedByDevice: row.updatedByDevice,
        hlc: row.hlc,
        deletedAt: row.deletedAt,
      ),
    );
  }

  RecurringTransactionsCompanion _companion(RecurringTransaction tx) {
    return RecurringTransactionsCompanion.insert(
      id: tx.id,
      templateJournalBuildJson: tx.templateJournalBuildJson,
      rrule: tx.rrule,
      nextDueAt: tx.nextDueAt,
      lastMaterialisedAt: Value(tx.lastMaterialisedAt),
      enabled: Value(tx.enabled),
      ownerUserId: tx.sync.ownerUserId,
      updatedAt: tx.sync.updatedAt,
      updatedByDevice: tx.sync.updatedByDevice,
      hlc: tx.sync.hlc,
    );
  }

  RecurringTransactionsCompanion _updateCompanion(RecurringTransaction tx) {
    return RecurringTransactionsCompanion(
      templateJournalBuildJson: Value(tx.templateJournalBuildJson),
      rrule: Value(tx.rrule),
      nextDueAt: Value(tx.nextDueAt),
      lastMaterialisedAt: Value(tx.lastMaterialisedAt),
      enabled: Value(tx.enabled),
      updatedAt: Value(tx.sync.updatedAt),
      updatedByDevice: Value(tx.sync.updatedByDevice),
      hlc: Value(tx.sync.hlc),
      deletedAt: Value(tx.sync.deletedAt),
    );
  }

  static DateTime _dateOnlyUtc(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}

class RecurringMaterialisationService {
  RecurringMaterialisationService({
    required RecurringTransactionRepository recurringRepository,
    required JournalEntryRepository journalEntryRepository,
    RecurrenceEngine recurrenceEngine = const RecurrenceEngine(),
  }) : _recurringRepository = recurringRepository,
       _journalEntryRepository = journalEntryRepository,
       _recurrenceEngine = recurrenceEngine;

  final RecurringTransactionRepository _recurringRepository;
  final JournalEntryRepository _journalEntryRepository;
  final RecurrenceEngine _recurrenceEngine;

  Future<int> materialiseDue(DateTime now, {int maxOccurrences = 100}) async {
    var materialised = 0;
    final due = await _recurringRepository.dueAt(now);
    for (final tx in due) {
      var current = tx;
      var guard = 0;
      while (!current.nextDueAt.isAfter(now) && guard < maxOccurrences) {
        final occurrence = current.nextDueAt;
        final journalId = journalEntryId(
          recurringTransactionId: current.id,
          occurrenceDate: occurrence,
        );
        final existing = await _journalEntryRepository.getById(journalId);
        if (existing == null) {
          final template = JournalBuildTemplateCodec.decode(
            current.templateJournalBuildJson,
          );
          await _journalEntryRepository.create(
            entry: template.entryForOccurrence(occurrence, id: journalId),
            postings: template.postings,
          );
          materialised++;
        }
        final nextDueAt = _recurrenceEngine.nextAfterRule(
          current.rrule,
          occurrence,
        );
        current = await _recurringRepository.markMaterialised(
          id: current.id,
          occurrenceDate: occurrence,
          nextDueAt: nextDueAt,
        );
        guard++;
      }
    }
    return materialised;
  }

  static String journalEntryId({
    required String recurringTransactionId,
    required DateTime occurrenceDate,
  }) {
    return 'recurring:$recurringTransactionId:${_yyyymmdd(occurrenceDate)}';
  }

  static String _yyyymmdd(DateTime value) {
    final date = DateTime.utc(value.year, value.month, value.day);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}${two(date.month)}${two(date.day)}';
  }
}

class JournalBuildTemplate {
  const JournalBuildTemplate({required this.entry, required this.postings});

  final JournalEntryDraft entry;
  final List<PostingDraft> postings;

  JournalEntryDraft entryForOccurrence(DateTime occurrence, {String? id}) {
    final date = DateTime.utc(
      occurrence.year,
      occurrence.month,
      occurrence.day,
    );
    final settlementOffset = entry.settledOn?.difference(entry.date).inDays;
    return JournalEntryDraft(
      id: id,
      date: date,
      settledOn: settlementOffset == null
          ? null
          : date.add(Duration(days: settlementOffset)),
      narration: entry.narration,
      payee: entry.payee,
      tagIds: entry.tagIds,
      flag: entry.flag,
    );
  }
}

class JournalBuildTemplateCodec {
  const JournalBuildTemplateCodec._();

  static String encode(JournalEntryBuild build) {
    return jsonEncode({
      'entry': _entryToJson(build.entry),
      'postings': build.postings.map(_postingToJson).toList(growable: false),
    });
  }

  static JournalBuildTemplate decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Template must be a JSON object.');
    }
    final map = Map<String, Object?>.from(decoded);
    final entryRaw = map['entry'];
    final postingsRaw = map['postings'];
    if (entryRaw is! Map || postingsRaw is! List) {
      throw const FormatException('Template requires entry and postings.');
    }
    return JournalBuildTemplate(
      entry: _entryFromJson(Map<String, Object?>.from(entryRaw)),
      postings: postingsRaw
          .map((p) => _postingFromJson(Map<String, Object?>.from(p as Map)))
          .toList(growable: false),
    );
  }

  static Map<String, Object?> _entryToJson(JournalEntryDraft entry) {
    return {
      'id': entry.id,
      'date': _iso(entry.date),
      'settled_on': _isoOrNull(entry.settledOn),
      'narration': entry.narration,
      'payee': entry.payee,
      'tag_ids': entry.tagIds,
      'flag': entry.flag.name,
    };
  }

  static JournalEntryDraft _entryFromJson(Map<String, Object?> json) {
    final tagIdsRaw = json['tag_ids'];
    return JournalEntryDraft(
      id: json['id'] as String?,
      date: DateTime.parse(json['date'] as String).toUtc(),
      settledOn: json['settled_on'] == null
          ? null
          : DateTime.parse(json['settled_on'] as String).toUtc(),
      narration: json['narration'] as String,
      payee: json['payee'] as String?,
      tagIds: tagIdsRaw is List
          ? tagIdsRaw.map((v) => v as String).toList(growable: false)
          : const <String>[],
      flag: EntryFlag.values.byName((json['flag'] as String?) ?? 'confirmed'),
    );
  }

  static Map<String, Object?> _postingToJson(PostingDraft posting) {
    return {
      'id': posting.id,
      'position': posting.position,
      'account_id': posting.accountId,
      'units': posting.units.toString(),
      'unit': posting.unit,
      'cost': posting.cost == null ? null : _costToJson(posting.cost!),
      'price': posting.price == null ? null : _priceToJson(posting.price!),
    };
  }

  static PostingDraft _postingFromJson(Map<String, Object?> json) {
    return PostingDraft(
      id: json['id'] as String?,
      position: json['position'] as int?,
      accountId: json['account_id'] as String,
      units: Decimal.parse(json['units'] as String),
      unit: json['unit'] as String,
      cost: json['cost'] == null
          ? null
          : _costFromJson(Map<String, Object?>.from(json['cost']! as Map)),
      price: json['price'] == null
          ? null
          : _priceFromJson(Map<String, Object?>.from(json['price']! as Map)),
    );
  }

  static Map<String, Object?> _costToJson(Cost cost) {
    return {
      'per_unit': cost.perUnit.toString(),
      'currency': cost.currency,
      'lot_id': cost.lotId,
      'acquired_on': _isoOrNull(cost.acquiredOn),
    };
  }

  static Cost _costFromJson(Map<String, Object?> json) {
    return Cost(
      perUnit: Decimal.parse(json['per_unit'] as String),
      currency: json['currency'] as String,
      lotId: json['lot_id'] as String?,
      acquiredOn: json['acquired_on'] == null
          ? null
          : DateTime.parse(json['acquired_on'] as String).toUtc(),
    );
  }

  static Map<String, Object?> _priceToJson(Price price) {
    return {'per_unit': price.perUnit.toString(), 'currency': price.currency};
  }

  static Price _priceFromJson(Map<String, Object?> json) {
    return Price(
      perUnit: Decimal.parse(json['per_unit'] as String),
      currency: json['currency'] as String,
    );
  }
}

String _iso(DateTime value) => value.toUtc().toIso8601String();
String? _isoOrNull(DateTime? value) => value?.toUtc().toIso8601String();
