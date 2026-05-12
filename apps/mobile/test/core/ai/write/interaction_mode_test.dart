// Wave 35 — deriveInteractionMode contract.
//
// Keep this table in sync with `policy/tool_policy.rs` propose entries
// and `docs/ai-architecture.md` §5.5. Any backend kindLabel rename
// must update both sides + this test.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/write/write.dart';

void main() {
  group('deriveInteractionMode', () {
    test('ExternalSideEffect always typed', () {
      const p = ExternalSideEffect(
        proposalId: 'p1',
        kindLabel: 'broker_order',
        summaryZh: 'place order',
        target: const ExternalTarget(system: 'broker', endpoint: 'opaque-1'),
        payload: const <String, Object?>{},
      );
      expect(deriveInteractionMode(p), InteractionMode.typed);
    });

    test('LocalImmediateWrite is swipe (already applied)', () {
      const p = LocalImmediateWrite(
        proposalId: 'p1',
        kindLabel: 'memo_edit',
        summaryZh: 'note edit',
        undo: UndoToken(token: 't', expiresAtIso: '2026-05-12T00:00:00Z'),
      );
      expect(deriveInteractionMode(p), InteractionMode.swipe);
    });

    test('LocalProposal is confirmDiff', () {
      const p = LocalProposal(
        proposalId: 'p1',
        kindLabel: 'recategorize_batch',
        summaryZh: 'recat',
        payload: <String, Object?>{},
      );
      expect(deriveInteractionMode(p), InteractionMode.confirmDiff);
    });

    test('CloudProposal kindLabel mapping table', () {
      final cases = <String, InteractionMode>{
        'broker_order': InteractionMode.typed,
        'bulk_delete': InteractionMode.typed,
        'rebalance': InteractionMode.confirmDiff,
        'liability_payment': InteractionMode.confirmDiff,
        'trade': InteractionMode.confirmDiff,
        'account_create': InteractionMode.confirmDiff,
        'asset_valuation': InteractionMode.confirmDiff,
        'expense': InteractionMode.oneTap,
        'memo_edit': InteractionMode.oneTap,
        'category_set': InteractionMode.oneTap,
        'tag_apply': InteractionMode.oneTap,
      };
      for (final entry in cases.entries) {
        final p = CloudProposal(
          proposalId: 'p1',
          kindLabel: entry.key,
          summaryZh: 's',
          toolName: 'propose_${entry.key}',
          payload: const <String, Object?>{},
        );
        expect(
          deriveInteractionMode(p),
          entry.value,
          reason: 'kindLabel=${entry.key}',
        );
      }
    });

    test('unknown CloudProposal kindLabel falls back to confirmDiff', () {
      const p = CloudProposal(
        proposalId: 'p1',
        kindLabel: 'newfangled_action',
        summaryZh: 's',
        toolName: 'propose_newfangled',
        payload: <String, Object?>{},
      );
      expect(deriveInteractionMode(p), InteractionMode.confirmDiff);
    });
  });
}
