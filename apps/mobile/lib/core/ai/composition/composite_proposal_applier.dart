/// Routes a confirmed [ReadyProposalPlan] to the owning domain's
/// [ProposalApplier] (`docs/lifeos-shell.md` §4, `docs/knowledgeos-domain.md`
/// §15.6).
///
/// The chat surface has exactly one `proposalApplierProvider`, but a
/// multi-domain build needs Finance *and* KnowledgeOS (and later more) to
/// each own their `propose_*` kinds. This composite holds one primary
/// applier per domain keyed by the kinds it claims, with a fallback for
/// everything unclaimed. Dispatch is by `plan.kind` on apply; undo has no
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
    required this.tablePrefix,
  });

  final ProposalApplier applier;

  /// `propose_*` wire kinds this applier handles (e.g. `knowledge_merge`).
  final Set<String> kinds;

  /// Prefix of the Drift table names this applier writes (e.g.
  /// `knowledge_`). Used to route [undo] since [ProposalApplyState] keeps
  /// the table, not the originating kind.
  final String tablePrefix;
}

class CompositeProposalApplier implements ProposalApplier {
  CompositeProposalApplier({required this.routes, required this.fallback});

  /// Domain routes tried in order on apply (first matching kind wins).
  final List<ProposalApplierRoute> routes;

  /// Applier for any kind no route claims — the previous single-domain
  /// behaviour (FinanceOS today).
  final ProposalApplier fallback;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) {
    for (final r in routes) {
      if (r.kinds.contains(plan.kind)) return r.applier.apply(plan);
    }
    return fallback.apply(plan);
  }

  @override
  Future<void> undo(ProposalApplyState state) {
    final table = state.appliedTable ?? '';
    for (final r in routes) {
      if (table.startsWith(r.tablePrefix)) return r.applier.undo(state);
    }
    return fallback.undo(state);
  }
}
