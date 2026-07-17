import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/core/ai/composition/composite_proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';

typedef DomainProposalApplierReader = Future<ProposalApplier> Function(Ref ref);

Future<ProposalApplierRoute> buildProposalApplierRoute(
  Ref ref, {
  required DomainProposalApplierReader readApplier,
  required Set<String> kinds,
  required Set<String> tablePrefixes,
}) async {
  return ProposalApplierRoute(
    applier: _LazyProposalApplier(() => readApplier(ref)),
    kinds: kinds,
    tablePrefixes: tablePrefixes,
  );
}

/// Defers repository-heavy domain applier construction until the composite
/// has selected this route by proposal kind or undo table. Without this, an
/// Execution-only confirmation waits for every active Finance, Knowledge,
/// and Execution repository graph to initialize.
final class _LazyProposalApplier implements ProposalApplier {
  _LazyProposalApplier(this._read);

  final Future<ProposalApplier> Function() _read;
  Future<ProposalApplier>? _resolved;

  Future<ProposalApplier> _resolve() => _resolved ??= _read();

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    return (await _resolve()).apply(plan);
  }

  @override
  Future<void> undo(ProposalApplyState state) async {
    return (await _resolve()).undo(state);
  }
}
