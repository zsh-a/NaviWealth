import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/persistence/providers.dart';
import '../../../../core/sync/providers.dart';

/// Per-table row counts from local Finance tables, for the Sync Status
/// page. Lives in `features/finance/` because the table names are
/// Finance schema; HealthOS / KnowledgeOS will add their own diagnostic
/// providers alongside this one (the Settings page composes the result).
typedef LocalTableCounts = Map<String, int>;

/// Wire identifiers for the diagnostic counters, in display order.
const List<String> kFinanceLocalCountIds = [
  'accounts_user',
  'accounts_system',
  'journal_entries',
  'postings',
  'assets',
  'prices',
  'watchlist_items',
  'recurring_transactions',
  'liabilities',
  'tags',
];

const String _kLocalCountsSql = '''
  SELECT 'accounts_user'   AS t, COUNT(*) AS c FROM accounts          WHERE id NOT LIKE 'system-account:%' AND deleted_at IS NULL
  UNION ALL SELECT 'accounts_system',  COUNT(*) FROM accounts         WHERE id LIKE 'system-account:%' AND deleted_at IS NULL
  UNION ALL SELECT 'journal_entries',  COUNT(*) FROM journal_entries  WHERE deleted_at IS NULL
  UNION ALL SELECT 'postings',         COUNT(*) FROM postings         WHERE deleted_at IS NULL
  UNION ALL SELECT 'assets',           COUNT(*) FROM assets           WHERE deleted_at IS NULL
  UNION ALL SELECT 'prices',           COUNT(*) FROM prices           WHERE deleted_at IS NULL
  UNION ALL SELECT 'watchlist_items',  COUNT(*) FROM watchlist_items  WHERE deleted_at IS NULL
  UNION ALL SELECT 'recurring_transactions', COUNT(*) FROM recurring_transactions WHERE deleted_at IS NULL
  UNION ALL SELECT 'liabilities',      COUNT(*) FROM liabilities      WHERE deleted_at IS NULL
  UNION ALL SELECT 'tags',             COUNT(*) FROM tags             WHERE deleted_at IS NULL
''';

final financeLocalTableCountsProvider = FutureProvider<LocalTableCounts>((
  ref,
) async {
  ref.watch(syncStatusEventStreamProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  final rows = await db.customSelect(_kLocalCountsSql).get();
  return {for (final r in rows) r.read<String>('t'): r.read<int>('c')};
});
