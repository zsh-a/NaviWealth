import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/db/app_database.dart';
import '../auth/auth_session.dart';
import 'op.dart';
import 'op_outbox.dart';
import 'sync_engine.dart';

/// Queues one-time insert ops for local rows that pre-date the sync outbox.
///
/// This is intentionally a client-side migration: older installs may already
/// have accounts/assets/ledger rows, but no corresponding `op_outbox` rows.
/// Without this, a fresh device can pull only rows created after sync was
/// enabled.
class SyncBackfill {
  SyncBackfill({
    required AppDatabase db,
    required OutboxStore outbox,
    required SyncEngine engine,
    required AuthSession session,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _outbox = outbox,
       _engine = engine,
       _session = session,
       _uuid = uuid;

  final AppDatabase _db;
  final OutboxStore _outbox;
  final SyncEngine _engine;
  final AuthSession _session;
  final Uuid _uuid;

  static const version = '2';

  Future<int> enqueueMissingLocalRows() async {
    final key =
        'sync.backfill.$version.${_session.userId}.${_session.deviceId}';
    final existing = await _db
        .customSelect(
          'SELECT value FROM sync_meta WHERE key = ?',
          variables: [Variable.withString(key)],
        )
        .getSingleOrNull();
    if (existing != null) return 0;

    var queued = 0;
    queued += await _backfillAccounts();
    queued += await _backfillAssets();
    queued += await _backfillPrices();
    queued += await _backfillJournalEntries();
    queued += await _backfillPostings();
    queued += await _backfillLiabilities();
    queued += await _backfillAmortizationEntries();
    queued += await _backfillUsers();
    queued += await _backfillSettings();
    queued += await _backfillCategories();
    queued += await _backfillTagLinks();

    await _db.customStatement(
      'INSERT INTO sync_meta(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, DateTime.now().toUtc().toIso8601String()],
    );
    return queued;
  }

  Future<int> _backfillAccounts() async {
    final rows = (await _db.select(_db.accounts).get())
        .where(
          (r) =>
              r.ownerUserId == _session.userId &&
              r.deletedAt == null &&
              !r.id.startsWith('system-account:'),
        )
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('accounts', r.id, (sync) {
        return {
          'id': r.id,
          'type': r.type.name,
          'name': r.name,
          'currency': r.currency,
          'category': r.category.name,
          'institution': r.institution,
          'account_number': r.accountNumber,
          'note': r.note,
          'archived': r.archived,
          'parent_id': r.parentId,
          'icon': r.icon,
          'color': r.color,
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<int> _backfillAssets() async {
    final rows = (await _db.select(_db.assets).get())
        .where((r) => r.ownerUserId == _session.userId && r.deletedAt == null)
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('assets', r.id, (sync) {
        return {
          'id': r.id,
          'type': r.type.name,
          'symbol': r.symbol,
          'currency': r.currency,
          'name': r.name,
          'market': r.market,
          'industry': r.industry,
          'region': r.region,
          'isin': r.isin,
          'logo_url': r.logoUrl,
          'metadata_json': r.metadataJson,
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<int> _backfillPrices() async {
    final rows = (await _db.select(_db.prices).get())
        .where((r) => r.ownerUserId == _session.userId && r.deletedAt == null)
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('prices', r.id, (sync) {
        return {
          'id': r.id,
          'unit': r.unit,
          'quote_currency': r.quoteCurrency,
          'observed_on': _iso(r.observedOn),
          'per_unit': r.perUnit.toString(),
          'source': r.source,
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<int> _backfillJournalEntries() async {
    final rows = (await _db.select(_db.journalEntries).get())
        .where((r) => r.ownerUserId == _session.userId && r.deletedAt == null)
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('journal_entries', r.id, (sync) {
        return {
          'id': r.id,
          'date': _iso(r.date),
          'settled_on': _isoOrNull(r.settledOn),
          'narration': r.narration,
          'payee': r.payee,
          'flag': r.flag.name,
          'tag_ids_json': r.tagIdsJson,
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<int> _backfillPostings() async {
    final rows = (await _db.select(_db.postings).get())
        .where((r) => r.ownerUserId == _session.userId && r.deletedAt == null)
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('postings', r.id, (sync) {
        return {
          'id': r.id,
          'journal_entry_id': r.journalEntryId,
          'position': r.position,
          'account_id': r.accountId,
          'units': r.units.toString(),
          'unit': r.unit,
          'cost_per_unit': r.costPerUnit?.toString(),
          'cost_currency': r.costCurrency,
          'cost_lot_id': r.costLotId,
          'cost_acquired_on': _isoOrNull(r.costAcquiredOn),
          'price_per_unit': r.pricePerUnit?.toString(),
          'price_currency': r.priceCurrency,
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<int> _backfillLiabilities() async {
    final rows = (await _db.select(_db.liabilities).get())
        .where((r) => r.ownerUserId == _session.userId && r.deletedAt == null)
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('liabilities', r.id, (sync) {
        return {
          'id': r.id,
          'type': r.type.name,
          'name': r.name,
          'principal': r.principal.toString(),
          'interest_rate': r.interestRate.toString(),
          'currency': r.currency,
          'payment_method': r.paymentMethod.name,
          'rate_type': r.rateType.name,
          'account_id': r.accountId,
          'start_date': _isoOrNull(r.startDate),
          'end_date': _isoOrNull(r.endDate),
          'term_months': r.termMonths,
          'monthly_payment': r.monthlyPayment?.toString(),
          'statement_day': r.statementDay,
          'payment_due_day': r.paymentDueDay,
          'note': r.note,
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<int> _backfillAmortizationEntries() async {
    final rows = (await _db.select(_db.amortizationEntries).get())
        .where((r) => r.ownerUserId == _session.userId && r.deletedAt == null)
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('amortization_entries', r.id, (sync) {
        return {
          'id': r.id,
          'liability_id': r.liabilityId,
          'period_index': r.periodIndex,
          'due_date': _iso(r.dueDate),
          'principal_payment': r.principalPayment.toString(),
          'interest_payment': r.interestPayment.toString(),
          'remaining_balance': r.remainingBalance.toString(),
          'paid_at': _isoOrNull(r.paidAt),
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<int> _backfillUsers() async {
    final rows = (await _db.select(_db.users).get())
        .where((r) => r.ownerUserId == _session.userId && r.deletedAt == null)
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('users', r.id, (sync) {
        return {
          'id': r.id,
          'name': r.name,
          'email': r.email,
          'created_at': _iso(r.createdAt),
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<int> _backfillSettings() async {
    final rows = (await _db.select(_db.settingsTable).get())
        .where((r) => r.ownerUserId == _session.userId && r.deletedAt == null)
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('settings', r.userId, (sync) {
        return {
          'user_id': r.userId,
          'base_currency': r.baseCurrency,
          'theme_mode': r.themeMode.name,
          'privacy_mode': r.privacyMode.name,
          'cost_basis_method': r.costBasisMethod.name,
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<int> _backfillCategories() async {
    final rows = (await _db.select(_db.categories).get())
        .where((r) => r.ownerUserId == _session.userId && r.deletedAt == null)
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('categories', r.id, (sync) {
        return {
          'id': r.id,
          'name': r.name,
          'parent_id': r.parentId,
          'sort_order': r.sortOrder,
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<int> _backfillTagLinks() async {
    final rows = (await _db.select(_db.tagLinks).get())
        .where((r) => r.ownerUserId == _session.userId && r.deletedAt == null)
        .toList(growable: false);
    var count = 0;
    for (final r in rows) {
      await _enqueue('tag_links', r.id, (sync) {
        return {
          'id': r.id,
          'tag_id': r.tagId,
          'entity_table': r.entityTable,
          'entity_id': r.entityId,
          ...sync,
        };
      });
      count++;
    }
    return count;
  }

  Future<void> _enqueue(
    String table,
    String rowId,
    Map<String, Object?> Function(Map<String, Object?> sync) fields,
  ) async {
    final hlc = await _engine.stampHlc();
    final sync = {
      'owner_user_id': _session.userId,
      'updated_at': _iso(hlc.wallTime),
      'updated_by_device': _session.deviceId,
      'hlc': hlc.toString(),
    };
    await _outbox.enqueue(
      Op(
        opId: _uuid.v4(),
        tableName: table,
        rowId: rowId,
        opType: OpType.insert,
        fieldsDiff: fields(sync),
        hlc: hlc,
        deviceId: _session.deviceId,
      ),
    );
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();
  String? _isoOrNull(DateTime? value) => value?.toUtc().toIso8601String();
}
