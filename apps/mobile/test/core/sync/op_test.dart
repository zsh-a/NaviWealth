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
      // Mirror of the syncable Drift table inventory. Updating the row-state
      // sync surface without this closed-set test is the bug it catches.
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
        'corporate_actions',
        'watchlist_items',
        // Options Income Planner P0 (`docs/options-income.md`).
        'options_strategy_profile',
        'approved_underlyings',
        // Options Income Planner P3 — trade journal.
        'options_trade_journal',
        // HealthOS (`docs/healthos-domain.md` §6.1).
        'health_metrics',
        // KnowledgeOS (`docs/knowledgeos-domain.md` §9) — all seven tables
        // ride the row-state protocol under the `know:` row family.
        'knowledge_notes',
        'knowledge_principles',
        'knowledge_assumptions',
        'knowledge_decisions',
        'knowledge_concepts',
        'knowledge_experiments',
        'knowledge_routines',
        // ExecutionOS (`docs/executionos-domain.md`) — project/action kernel
        // under the `exec:` row family.
        'execution_projects',
        'execution_actions',
        'execution_commitments',
        'execution_progress_entries',
      };
      expect(kSyncableTables, expected);
    });
  });
}
