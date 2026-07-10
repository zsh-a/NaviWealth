import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/op_outbox.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/features/finance/domain/models/journal_entry.dart';
import 'package:naviwealth/features/finance/domain/models/posting.dart';
import 'package:uuid/uuid.dart';

part 'journal_entry_repository_activity_feed.dart';
part 'journal_entry_repository_mappers.dart';
part 'journal_entry_repository_models.dart';
part 'journal_entry_repository_reads.dart';
part 'journal_entry_repository_writes.dart';

/// Drift DAO for `journal_entries` + `postings`. Models a JE
/// and its postings as one logical unit: every public mutation lives
/// inside a single Drift transaction that writes the JE row, the
/// posting rows, and queues the corresponding outbox `Op`s atomically.
///
/// Balance enforcement: every `create` / `replacePostings` call routes
/// through [evaluateEntryBalance]. A non-balanced JE throws
/// [JournalEntryUnbalancedException]; the writer never commits a half-
/// balanced ledger.
///
/// What this repository deliberately does NOT do:
///   - Build the legs for a buy / sell / transfer (that's the
///     `JournalEntryBuilders` surface — this DAO is the persistence
///     backend the builders sit on top of).
///   - Run cost-basis selection (FIFO / LIFO) — `cost.lotId` is taken
///     verbatim from the caller.
///   - Refresh derived holdings; readers query postings directly.
class JournalEntryRepository
    with
        JournalEntryRepositoryReadMixin,
        JournalEntryRepositoryActivityFeedMixin,
        JournalEntryRepositoryWriteMixin {
  JournalEntryRepository({
    required AppDatabase db,
    required OutboxStore outbox,
    required MutationStamper stamper,
    required FxRateSource fxRateSource,
    required String baseCurrency,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _stamper = stamper,
       _fx = fxRateSource,
       _baseCurrency = baseCurrency,
       _uuid = uuid;

  @override
  final AppDatabase _db;
  @override
  final OutboxStore _outbox;
  @override
  final MutationStamper _stamper;
  @override
  final FxRateSource _fx;
  @override
  final String _baseCurrency;
  @override
  final Uuid _uuid;

  static const String _journalTable = 'journal_entries';
  static const String _postingsTable = 'postings';

  bool isBoundTo(AppDatabase database) =>
      identical(_db, database) && isOutboxBoundToDatabase(_outbox, database);
}
