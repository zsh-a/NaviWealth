import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
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

    test('proposal kind modes are not derived from kind labels here', () {
      const p = LocalProposal(
        proposalId: 'p1',
        kindLabel: 'expense',
        summaryZh: 'small expense',
        payload: <String, Object?>{},
      );
      expect(deriveInteractionMode(p), InteractionMode.confirmDiff);
    });

    test('ReadyProposalPlan derives from envelope kind', () {
      ReadyProposalPlan plan(ProposalEnvelopeKind kind) => ReadyProposalPlan(
        proposalId: 'p',
        kind: 'expense',
        envelopeKind: kind,
        summaryZh: 's',
        payload: const <String, Object?>{},
      );

      expect(
        deriveInteractionModeForPlan(plan(ProposalEnvelopeKind.localImmediate)),
        InteractionMode.swipe,
      );
      expect(
        deriveInteractionModeForPlan(plan(ProposalEnvelopeKind.localProposal)),
        InteractionMode.confirmDiff,
      );
      expect(
        deriveInteractionModeForPlan(
          plan(ProposalEnvelopeKind.externalSideEffect),
        ),
        InteractionMode.typed,
      );
      expect(
        deriveInteractionModeForPlan(plan(ProposalEnvelopeKind.unknown)),
        InteractionMode.typed,
      );
    });

    test('BatchProposalPlan uses most conservative child mode', () {
      const batch = BatchProposalPlan(
        proposalId: 'batch',
        kind: 'batch',
        summaryZh: 'batch',
        children: <ReadyProposalPlan>[
          ReadyProposalPlan(
            proposalId: 'a',
            kind: 'expense',
            envelopeKind: ProposalEnvelopeKind.localImmediate,
            summaryZh: 'a',
            payload: <String, Object?>{},
          ),
          ReadyProposalPlan(
            proposalId: 'b',
            kind: 'trade',
            envelopeKind: ProposalEnvelopeKind.localProposal,
            summaryZh: 'b',
            payload: <String, Object?>{},
          ),
        ],
      );

      expect(deriveInteractionModeForPlan(batch), InteractionMode.confirmDiff);
    });
  });

  group('BatchProposal envelope (M-2)', () {
    LocalImmediateWrite immediate(String token) {
      return LocalImmediateWrite(
        proposalId: 'p_$token',
        kindLabel: 'memo_edit',
        summaryZh: 'edit',
        undo: UndoToken(token: token, expiresAtIso: '2026-05-12T00:00:00Z'),
      );
    }

    LocalProposal proposal(String id) {
      return LocalProposal(
        proposalId: id,
        kindLabel: 'recategorize_batch',
        summaryZh: 'recat',
        payload: const <String, Object?>{},
      );
    }

    test('rejects empty children at construction', () {
      expect(
        () => BatchProposal(
          proposalId: 'b1',
          kindLabel: 'batch_apply',
          summaryZh: '5 edits',
          children: const [],
          undo: const BatchUndoToken(
            tokens: [],
            expiresAtIso: '2026-05-12T00:00:00Z',
          ),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects ExternalSideEffect children', () {
      expect(
        () => BatchProposal(
          proposalId: 'b1',
          kindLabel: 'batch_apply',
          summaryZh: 'mixed',
          children: [
            immediate('t1'),
            const ExternalSideEffect(
              proposalId: 'p_x',
              kindLabel: 'broker_order',
              summaryZh: 'place order',
              target: ExternalTarget(system: 'broker', endpoint: 'op-1'),
              payload: <String, Object?>{},
            ),
          ],
          undo: const BatchUndoToken(
            tokens: [],
            expiresAtIso: '2026-05-12T00:00:00Z',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects nested batches', () {
      final inner = BatchProposal(
        proposalId: 'b_inner',
        kindLabel: 'batch_apply',
        summaryZh: 'inner',
        children: [immediate('t1')],
        undo: const BatchUndoToken(
          tokens: [],
          expiresAtIso: '2026-05-12T00:00:00Z',
        ),
      );
      expect(
        () => BatchProposal(
          proposalId: 'b_outer',
          kindLabel: 'batch_apply',
          summaryZh: 'outer',
          children: [immediate('t2'), inner],
          undo: const BatchUndoToken(
            tokens: [],
            expiresAtIso: '2026-05-12T00:00:00Z',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('envelopeKind discriminator is "batch"', () {
      final batch = BatchProposal(
        proposalId: 'b1',
        kindLabel: 'batch_apply',
        summaryZh: '5 edits',
        children: [immediate('t1')],
        undo: const BatchUndoToken(
          tokens: [],
          expiresAtIso: '2026-05-12T00:00:00Z',
        ),
      );
      expect(batch.envelopeKind, 'batch');
    });

    test(
      'mode: all-immediate children → swipe (already applied semantics)',
      () {
        final batch = BatchProposal(
          proposalId: 'b1',
          kindLabel: 'batch_apply',
          summaryZh: '3 edits',
          children: [immediate('t1'), immediate('t2'), immediate('t3')],
          undo: const BatchUndoToken(
            tokens: [],
            expiresAtIso: '2026-05-12T00:00:00Z',
          ),
        );
        expect(deriveInteractionMode(batch), InteractionMode.swipe);
      },
    );

    test(
      'mode: presence of LocalProposal upgrades the batch to confirmDiff',
      () {
        final batch = BatchProposal(
          proposalId: 'b1',
          kindLabel: 'batch_apply',
          summaryZh: 'mixed',
          children: [immediate('t1'), proposal('p1')],
          undo: const BatchUndoToken(
            tokens: [],
            expiresAtIso: '2026-05-12T00:00:00Z',
          ),
        );
        expect(deriveInteractionMode(batch), InteractionMode.confirmDiff);
      },
    );
  });
}
