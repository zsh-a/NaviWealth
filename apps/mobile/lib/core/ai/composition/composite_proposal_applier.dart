/// Routes a confirmed [ReadyProposalPlan] to the owning domain's
/// [ProposalApplier] (`docs/architecture/lifeos-shell.md` §4, `docs/domains/knowledgeos-domain.md`
/// §15.6).
///
/// The chat surface has exactly one `proposalApplierProvider`, but a
/// multi-domain build needs Finance *and* KnowledgeOS (and later more) to
/// each own their `propose_*` kinds. This composite holds one primary
/// applier per domain keyed by the kinds it claims. Dispatch is by
/// `plan.kind` on apply; undo has no
/// kind, so it routes on the persisted `appliedTable` prefix instead.
library;

import 'proposal_applier.dart';
import 'proposal_apply_state.dart';
import 'proposal_plan.dart';

/// One domain's applier plus the proposal kinds + table prefix it owns.
class ProposalApplierRoute {
  const ProposalApplierRoute({
    required this.applier,
    required this.kinds,
    required this.tablePrefixes,
  });

  final ProposalApplier applier;

  /// `propose_*` wire kinds this applier handles (e.g. `knowledge_merge`).
  final Set<String> kinds;

  /// Prefixes of the Drift table names this applier writes (e.g.
  /// `knowledge_`, `journal_entries`). Used to route [undo] since
  /// [ProposalApplyState] keeps the table, not the originating kind.
  final Set<String> tablePrefixes;
}

class CompositeProposalApplier
    implements ProposalApplier, ProposalCancellationHandler {
  CompositeProposalApplier({required this.routes});

  /// Domain routes tried in order on apply (first matching kind wins).
  final List<ProposalApplierRoute> routes;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) {
    for (final r in routes) {
      if (r.kinds.contains(plan.kind)) return r.applier.apply(plan);
    }
    throw ProposalApplyException(
      'no proposal applier registered for kind: ${plan.kind}',
    );
  }

  @override
  Future<void> undo(ProposalApplyState state) {
    final table = state.appliedTable ?? '';
    for (final r in routes) {
      if (r.tablePrefixes.any(table.startsWith)) {
        return r.applier.undo(state);
      }
    }
    throw ProposalApplyException(
      'no proposal applier registered for table: $table',
    );
  }

  @override
  Future<void> cancel(ReadyProposalPlan plan) async {
    for (final route in routes) {
      if (!route.kinds.contains(plan.kind)) continue;
      final applier = route.applier;
      if (applier is ProposalCancellationHandler) {
        await (applier as ProposalCancellationHandler).cancel(plan);
      }
      return;
    }
  }
}
