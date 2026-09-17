import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/current_user.dart';
import '../../auth/providers.dart' as auth;
import '../composition/proposal_applier.dart';
import '../composition/proposal_apply_state.dart';
import '../composition/proposal_plan.dart';
import 'providers.dart';
import 'scheduled_agent_store.dart';
import 'scheduled_agent_task.dart';

class ScheduledTaskApplier implements ProposalApplier {
  const ScheduledTaskApplier(this.ref);
  final Ref ref;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    final owner = await ref.read(currentUserIdProvider)();
    final task = ScheduledAgentTask.fromJson(
      Map<String, Object?>.from(plan.payload['task']! as Map),
    );
    if (plan.kind != 'scheduled_task' ||
        plan.payload['owner_user_id'] != owner ||
        task.id != 'user_task:${plan.proposalId}' ||
        task.revision != 1 ||
        !(await ref.read(auth.domainOptInsProvider.future))
            .contains(task.domain)) {
      throw ProposalApplyException(
        'Task permission changed; create a new proposal',
      );
    }
    final store = await ref.read(scheduledAgentStoreProvider.future);
    if (store.ownerUserId != owner) {
      throw ProposalApplyException('Task owner changed');
    }
    final existing = (await store.list())
        .where((row) => row.id == task.id)
        .firstOrNull;
    if (existing != null) throw ProposalApplyException('Task already exists');
    await store.save(task, expectedRevision: 0);
    ref.invalidate(scheduledAgentTasksProvider);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: task.id,
      appliedTable: 'scheduled_agent_tasks',
      appliedAt: DateTime.now().toUtc(),
      undoData: {'owner_user_id': owner},
      shortLabel: task.title,
    );
  }

  @override
  Future<void> undo(ProposalApplyState state) async {
    final owner = await ref.read(currentUserIdProvider)();
    if (owner != state.undoData?['owner_user_id'] ||
        !state.isUndoableAt(DateTime.now().toUtc())) {
      throw ProposalApplyException('Task undo is no longer available');
    }
    // Keep report/history identities; undo revokes all future runs.
    await (await ref.read(agentPreferenceStoreProvider.future)).setEnabled(
      ownerUserId: owner,
      agentId: state.appliedEntityId!,
      enabled: false,
      updatedAt: DateTime.now().toUtc(),
    );
    ref.invalidate(scheduledAgentTasksProvider);
  }
}
