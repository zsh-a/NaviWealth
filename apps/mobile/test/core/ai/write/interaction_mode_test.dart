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
        target: ExternalTarget(system: 'broker', endpoint: 'opaque-1'),
        payload: <String, Object?>{},
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

    test(
      'interactionModeForKindLabel covers every device propose kindLabel',
      () {
        // The propose_card flow calls interactionModeForKindLabel(_kindLabel(plan.kind))
        // directly; this table is the authoritative mapping post-CloudProposal removal.
        const labels = <String, InteractionMode>{
          'expense': InteractionMode.oneTap,
          'memo_edit': InteractionMode.oneTap,
          'category_set': InteractionMode.oneTap,
          'tag_apply': InteractionMode.oneTap,
          'trade': InteractionMode.confirmDiff,
          'rebalance': InteractionMode.confirmDiff,
          'liability_payment': InteractionMode.confirmDiff,
          'account_create': InteractionMode.confirmDiff,
          'asset_valuation': InteractionMode.confirmDiff,
          'broker_order': InteractionMode.typed,
          'bulk_delete': InteractionMode.typed,
          'unknown_kind': InteractionMode.confirmDiff,
        };
        for (final entry in labels.entries) {
          expect(
            interactionModeForKindLabel(entry.key),
            entry.value,
            reason: 'kindLabel=${entry.key}',
          );
        }
      },
    );

    test('unknown kindLabel falls back to confirmDiff', () {
      expect(
        interactionModeForKindLabel('newfangled_action'),
        InteractionMode.confirmDiff,
      );
    });
  });
}
