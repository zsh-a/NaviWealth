import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/domain_packs/proposal_applier_route.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';

void main() {
  test('domain proposal applier is lazy and memoized', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var reads = 0;
    final probe = FutureProvider((ref) async {
      final route = await buildProposalApplierRoute(
        ref,
        readApplier: (_) async {
          reads += 1;
          return const _RecordingApplier();
        },
        kinds: const <String>{'execution_action'},
        tablePrefixes: const <String>{'execution_'},
      );
      expect(reads, 0);
      const plan = ReadyProposalPlan(
        proposalId: 'proposal-1',
        kind: 'execution_action',
        summaryZh: 'Action',
        payload: <String, Object?>{},
      );
      await route.applier.apply(plan);
      await route.applier.apply(plan);
      return reads;
    });

    expect(await container.read(probe.future), 1);
  });
}

final class _RecordingApplier implements ProposalApplier {
  const _RecordingApplier();

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    return const ProposalApplyState(status: ProposalApplyStatus.applied);
  }

  @override
  Future<void> undo(ProposalApplyState state) async {}
}
