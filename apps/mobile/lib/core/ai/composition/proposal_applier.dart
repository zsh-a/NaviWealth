/// Cross-domain seam for the chat propose-card apply path
/// (`docs/lifeos-shell.md` §4, D-1.6b).
///
/// The chat surface accepts confirmed `propose_*` plans and dispatches
/// them to a domain-owned [ProposalApplier] for the actual repository
/// write + optional undo. Each domain (Finance today, HealthOS later)
/// provides its own concrete applier; `bootstrap.dart` overrides
/// [proposalApplierProvider] with the active build's implementation.
///
/// The shell-only default returns a no-op applier that throws
/// [ProposalApplyException] on every [ProposalApplier.apply] — this
/// keeps the chat code path well-typed in builds where no domain has
/// registered, instead of forcing every caller to null-check.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'proposal_apply_state.dart';
import 'proposal_plan.dart';

class ProposalApplyException implements Exception {
  ProposalApplyException(this.message);
  final String message;

  @override
  String toString() => 'ProposalApplyException: $message';
}

/// Dispatch a confirmed [ReadyProposalPlan] to the matching domain
/// write, and reverse it again on undo.
///
/// Implementations live in `features/<domain>/composition/`. The chat
/// UI only depends on this interface.
abstract class ProposalApplier {
  Future<ProposalApplyState> apply(ReadyProposalPlan plan);
  Future<void> undo(ProposalApplyState state);
}

class _NoopProposalApplier implements ProposalApplier {
  const _NoopProposalApplier();

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    throw ProposalApplyException(
      'no proposal applier registered for this build',
    );
  }

  @override
  Future<void> undo(ProposalApplyState state) async {}
}

/// Active applier for the current build. Default is a no-op; domain
/// composition registers the real implementation in `bootstrap.dart`.
final proposalApplierProvider = FutureProvider<ProposalApplier>(
  (ref) async => const _NoopProposalApplier(),
);
