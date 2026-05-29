import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/row_applier.dart';

void main() {
  // Pin the forward-only sync enum so any future add / drop is a deliberate
  // schema change, not a silent edit.
  group('kSyncableTables', () {
    test('contains the FIR-130 ledger triple', () {
      expect(
        kSyncableTables,
        containsAll(<String>{'journal_entries', 'postings', 'prices'}),
      );
    });

    test('matches the documented closed set', () {
      // Mirror of `docs/sync-v2.md` §4. Updating either side without the
      // other is the bug this test catches.
      const expected = <String>{
        'accounts',
        'assets',
        'liabilities',
        'fx_rates',
        'tags',
        'tag_links',
        'budgets',
        'goals',
        'devices',
        'amortization_entries',
        'categories',
        'settings',
        'users',
        'journal_entries',
        'postings',
        'prices',
        'watchlist_items',
        // Options Income Planner P0 (`docs/options-income.md`).
        'options_strategy_profile',
        'approved_underlyings',
        // Options Income Planner P3 — trade journal.
        'options_trade_journal',
        // KnowledgeOS (`docs/knowledgeos-domain.md` §9) — all seven tables
        // ride the row-state protocol under the `know:` row family.
        'knowledge_notes',
        'knowledge_principles',
        'knowledge_assumptions',
        'knowledge_decisions',
        'knowledge_concepts',
        'knowledge_experiments',
        'knowledge_routines',
      };
      expect(kSyncableTables, expected);
    });
  });
}
