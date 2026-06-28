import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/ai_tools/list_open_actions_tool.dart';
import 'package:naviwealth/features/execution/ai_tools/propose_action_status_update_tool.dart';
import 'package:naviwealth/features/execution/ai_tools/propose_action_tool.dart';
import 'package:naviwealth/features/execution/ai_tools/propose_commitment_tool.dart';
import 'package:naviwealth/features/execution/ai_tools/propose_progress_tool.dart';
import 'package:naviwealth/features/execution/ai_tools/propose_project_tool.dart';
import 'package:naviwealth/features/execution/ai_tools/summarize_execution_progress_tool.dart';
import 'package:naviwealth/features/execution/composition/execution_proposal_applier.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution_ai_tools.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-exec-ai';
const _deviceId = 'dev-exec-ai';

DeviceSession _session() => DeviceSession(messages: []);

Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
}

ReadyProposalPlan _readyPlan(Object? proposal) {
  final plan = ProposalPlan.tryParse(proposal);
  expect(plan, isA<ReadyProposalPlan>());
  return plan! as ReadyProposalPlan;
}

Future<ProposalApplyState> _applyReadyPlan(
  ProviderContainer container,
  ReadyProposalPlan plan,
) {
  return _withRef(container, (ref) async {
    final applier = await ref.read(executionProposalApplierProvider.future);
    return applier.apply(plan);
  });
}

SyncMeta _sync(int tick) {
  final wall = DateTime.utc(2026, 6, 1, 9, 0, tick);
  return SyncMeta(
    ownerUserId: _userId,
    updatedAt: wall,
    updatedByDevice: _deviceId,
    hlc: Hlc(
      wallMillis: wall.millisecondsSinceEpoch,
      counter: 0,
      nodeId: _deviceId,
    ),
  );
}

MutationStamper _stamper() {
  var tick = 0;
  return MutationStamper(
    currentUserId: () async => _userId,
    deviceId: () async => _deviceId,
    stampHlc: () async {
      final meta = _sync(tick++);
      return meta.hlc;
    },
  );
}

ProviderContainer _container(AppDatabase db, InMemoryOutboxStore outbox) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((ref) async => db),
      outboxStoreProvider.overrideWith((ref) async => outbox),
      currentUserIdProvider.overrideWithValue(() async => _userId),
      mutationStamperProvider.overrideWith((ref) async => _stamper()),
    ],
  );
}

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late ProviderContainer container;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    container = _container(db, outbox);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('propose_action returns a ready proposal envelope', () async {
    final out = await _withRef(
      container,
      (ref) => const ProposeActionTool()
          .invoke(DeviceToolContext(ref: ref, session: _session()), const {
            'title': 'Review FIRE budget strain',
            'priority': 'high',
            'reason': '预算压力需要一个明确下一步',
            'source_domain': 'finance',
            'source_row_family': 'fin:budgets',
            'source_row_id': 'budget:2026-06',
            'source_label': 'June budget',
          }),
    );

    final proposal = out! as Map;
    expect(proposal['kind'], 'execution_action');
    expect(proposal['status'], 'ready');
    final payload = proposal['payload'] as Map;
    expect(payload['title'], 'Review FIRE budget strain');
    expect(payload['priority'], 'high');
    expect(payload['source_row_family'], 'fin:budgets');
  });

  test('propose_project returns a ready proposal envelope', () async {
    final out = await _withRef(
      container,
      (ref) => const ProposeProjectTool()
          .invoke(DeviceToolContext(ref: ref, session: _session()), const {
            'title': 'Ship ExecutionOS prod-basic',
            'description': 'Close MVP gaps before broader dogfooding.',
            'horizon': 'month',
            'target_date': '2026-06-30T00:00:00Z',
            'reason': 'ExecutionOS needs a bounded delivery container',
          }),
    );

    final proposal = out! as Map<Object?, Object?>;
    expect(proposal['kind'], 'execution_project');
    expect(proposal['status'], 'ready');
    final payload = proposal['payload']! as Map<Object?, Object?>;
    expect(payload['title'], 'Ship ExecutionOS prod-basic');
    expect(payload['horizon'], 'month');
    expect(payload['target_date'], '2026-06-30T00:00:00.000Z');
  });

  test('propose_commitment returns a ready proposal envelope', () async {
    final out = await _withRef(
      container,
      (ref) => const ProposeCommitmentTool()
          .invoke(DeviceToolContext(ref: ref, session: _session()), const {
            'title': 'Weekly execution review',
            'project_id': 'proj-execution',
            'reason': 'A recurring review keeps progress visible',
          }),
    );

    final proposal = out! as Map<Object?, Object?>;
    expect(proposal['kind'], 'execution_commitment');
    expect(proposal['status'], 'ready');
    final payload = proposal['payload']! as Map<Object?, Object?>;
    expect(payload['title'], 'Weekly execution review');
    expect(payload['project_id'], 'proj-execution');
    expect(payload['horizon'], 'open');
  });

  test('propose_progress returns a ready proposal envelope', () async {
    final out = await _withRef(
      container,
      (ref) => const ProposeProgressTool()
          .invoke(DeviceToolContext(ref: ref, session: _session()), const {
            'note': 'Blocked on final proposal coverage.',
            'kind': 'blocker',
            'action_id': 'act-ai',
            'reason': 'The blocker should be visible in review',
          }),
    );

    final proposal = out! as Map<Object?, Object?>;
    expect(proposal['kind'], 'execution_progress');
    expect(proposal['status'], 'ready');
    final payload = proposal['payload']! as Map<Object?, Object?>;
    expect(payload['note'], 'Blocked on final proposal coverage.');
    expect(payload['kind'], 'blocker');
    expect(payload['action_id'], 'act-ai');
  });

  test(
    'propose_action_status_update returns a ready proposal envelope',
    () async {
      final out = await _withRef(
        container,
        (ref) => const ProposeActionStatusUpdateTool()
            .invoke(DeviceToolContext(ref: ref, session: _session()), const {
              'action_id': 'act-ai',
              'status': 'done',
              'progress_note': 'Finished from chat follow-up.',
              'reason': '用户明确说这个行动已经完成',
            }),
      );

      final proposal = out! as Map<Object?, Object?>;
      expect(proposal['kind'], 'execution_action_status_update');
      expect(proposal['status'], 'ready');
      final payload = proposal['payload']! as Map<Object?, Object?>;
      expect(payload['action_id'], 'act-ai');
      expect(payload['status'], 'done');
      expect(payload['progress_note'], 'Finished from chat follow-up.');
    },
  );

  test(
    'execution prompt routes existing action status changes to proposals',
    () {
      expect(kExecutionSystemPromptBlock, contains('list_open_actions'));
      expect(
        kExecutionSystemPromptBlock,
        contains('propose_action_status_update'),
      );
      expect(kExecutionSystemPromptBlock, contains('不会直接写入'));
    },
  );

  test('execution proposal applier creates an action', () async {
    final proposal = await _withRef(
      container,
      (ref) => const ProposeActionTool()
          .invoke(DeviceToolContext(ref: ref, session: _session()), const {
            'title': 'Book Zone 2 workout',
            'project_id': 'proj-health',
            'reason': 'HealthOS recovery is good enough',
            'source_domain': 'finance',
            'source_row_family': 'fin:cashflow',
            'source_row_id': 'cashflow-2026-06',
            'source_label': 'June cashflow plan',
          }),
    );
    final plan = ProposalPlan.tryParse(proposal);
    expect(plan, isA<ReadyProposalPlan>());

    final state = await _withRef(container, (ref) async {
      final applier = await ref.read(executionProposalApplierProvider.future);
      return applier.apply(plan as ReadyProposalPlan);
    });

    final repo = await container.read(executionRepositoryProvider.future);
    final action = await repo.findAction(
      ownerUserId: _userId,
      id: state.appliedEntityId!,
    );
    expect(action, isNotNull);
    expect(action!.title, 'Book Zone 2 workout');
    expect(action.projectId, 'proj-health');
    expect(action.source.domain, 'finance');
    expect(action.source.rowFamily, 'fin:cashflow');
    expect(action.source.rowId, 'cashflow-2026-06');
    expect(action.source.labelSnapshot, 'June cashflow plan');
    expect(state.appliedTable, 'execution_actions');
  });

  test(
    'execution proposal applier preserves Health source refs on commitments',
    () async {
      final plan = _readyPlan(
        await _withRef(
          container,
          (ref) => const ProposeCommitmentTool()
              .invoke(DeviceToolContext(ref: ref, session: _session()), const {
                'title': 'Protect recovery before hard workouts',
                'reason': 'HealthOS trend flagged recovery risk',
                'source_domain': 'health',
                'source_row_family': 'health:health_metrics',
                'source_row_id': 'sleep-short-1',
                'source_label': 'Short sleep trend',
              }),
        ),
      );

      final state = await _applyReadyPlan(container, plan);
      final repo = await container.read(executionRepositoryProvider.future);
      final commitment = await repo.findCommitment(
        ownerUserId: _userId,
        id: state.appliedEntityId!,
      );

      expect(commitment, isNotNull);
      expect(commitment!.title, 'Protect recovery before hard workouts');
      expect(commitment.source.domain, 'health');
      expect(commitment.source.rowFamily, 'health:health_metrics');
      expect(commitment.source.rowId, 'sleep-short-1');
      expect(commitment.source.labelSnapshot, 'Short sleep trend');
      expect(state.appliedTable, 'execution_commitments');
    },
  );

  test('execution proposal applier updates and undoes action status', () async {
    final repo = await container.read(executionRepositoryProvider.future);
    await repo.upsertAction(
      ExecutionAction(
        id: 'a-status',
        title: 'Close AI status loop',
        status: ExecutionActionStatus.doing,
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(30),
      ),
    );

    final plan = _readyPlan(
      await _withRef(
        container,
        (ref) => const ProposeActionStatusUpdateTool()
            .invoke(DeviceToolContext(ref: ref, session: _session()), const {
              'action_id': 'a-status',
              'status': 'done',
              'progress_note': 'Completed through confirmed AI proposal.',
              'reason': '用户要求标记完成',
            }),
      ),
    );
    final state = await _applyReadyPlan(container, plan);

    final done = await repo.findAction(ownerUserId: _userId, id: 'a-status');
    final progress = await repo.listRecentProgress(ownerUserId: _userId);
    expect(done!.status, ExecutionActionStatus.done);
    expect(done.completedAt, isNotNull);
    expect(progress.single.note, 'Completed through confirmed AI proposal.');
    expect(progress.single.kind, ExecutionProgressKind.completion);
    expect(state.appliedTable, 'execution_actions');
    expect(state.undoData?['previous_status'], 'doing');

    await _withRef(container, (ref) async {
      final applier = await ref.read(executionProposalApplierProvider.future);
      await applier.undo(state);
    });

    final restored = await repo.findAction(
      ownerUserId: _userId,
      id: 'a-status',
    );
    final tombstonedProgress = await repo.findProgress(
      ownerUserId: _userId,
      id: progress.single.id,
    );
    expect(restored!.status, ExecutionActionStatus.doing);
    expect(restored.completedAt, isNull);
    expect(tombstonedProgress!.sync.deletedAt, isNotNull);
  });

  test(
    'execution proposal applier creates project commitment and progress',
    () async {
      final projectPlan = _readyPlan(
        await _withRef(
          container,
          (ref) => const ProposeProjectTool()
              .invoke(DeviceToolContext(ref: ref, session: _session()), const {
                'title': 'Close ExecutionOS MVP gaps',
                'horizon': 'month',
                'reason': 'The work is larger than one action',
              }),
        ),
      );
      final projectState = await _applyReadyPlan(container, projectPlan);

      final repo = await container.read(executionRepositoryProvider.future);
      final project = await repo.findProject(
        ownerUserId: _userId,
        id: projectState.appliedEntityId!,
      );
      expect(project, isNotNull);
      expect(project!.title, 'Close ExecutionOS MVP gaps');
      expect(project.horizon, ExecutionHorizon.month);
      expect(projectState.appliedTable, 'execution_projects');

      final commitmentPlan = _readyPlan(
        await _withRef(
          container,
          (ref) => const ProposeCommitmentTool()
              .invoke(DeviceToolContext(ref: ref, session: _session()), {
                'title': 'Review execution every Friday',
                'project_id': project.id,
                'reason': 'Weekly review keeps the system useful',
              }),
        ),
      );
      final commitmentState = await _applyReadyPlan(container, commitmentPlan);
      final commitment = await repo.findCommitment(
        ownerUserId: _userId,
        id: commitmentState.appliedEntityId!,
      );
      expect(commitment, isNotNull);
      expect(commitment!.title, 'Review execution every Friday');
      expect(commitment.projectId, project.id);
      expect(commitmentState.appliedTable, 'execution_commitments');

      final progressPlan = _readyPlan(
        await _withRef(
          container,
          (ref) => const ProposeProgressTool()
              .invoke(DeviceToolContext(ref: ref, session: _session()), {
                'note': 'Proposal flow now covers all ExecutionOS entities.',
                'kind': 'completion',
                'project_id': project.id,
                'commitment_id': commitment.id,
                'reason': 'Review should show the completed system improvement',
              }),
        ),
      );
      final progressState = await _applyReadyPlan(container, progressPlan);
      final progress = await repo.findProgress(
        ownerUserId: _userId,
        id: progressState.appliedEntityId!,
      );
      expect(progress, isNotNull);
      expect(progress!.kind, ExecutionProgressKind.completion);
      expect(progress.projectId, project.id);
      expect(progress.commitmentId, commitment.id);
      expect(progressState.appliedTable, 'execution_progress_entries');

      await _withRef(container, (ref) async {
        final applier = await ref.read(executionProposalApplierProvider.future);
        await applier.undo(progressState);
      });
      final tombstonedProgress = await repo.findProgress(
        ownerUserId: _userId,
        id: progressState.appliedEntityId!,
      );
      expect(tombstonedProgress, isNotNull);
      expect(tombstonedProgress!.sync.deletedAt, isNotNull);
    },
  );

  test('list_open_actions reads repository-backed actions', () async {
    final repo = ExecutionRepository(db: db, outbox: outbox);
    await repo.upsertProject(
      ExecutionProject(
        id: 'proj-ai',
        title: 'AI execution context',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(8),
      ),
    );
    await repo.upsertCommitment(
      ExecutionCommitment(
        id: 'commit-ai',
        title: 'Weekly execution review',
        projectId: 'proj-ai',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(9),
      ),
    );
    await repo.upsertAction(
      ExecutionAction(
        id: 'a1',
        title: 'Triage inbox actions',
        projectId: 'proj-ai',
        commitmentId: 'commit-ai',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(10),
      ),
    );

    final out = await _withRef(
      container,
      (ref) => const ListOpenActionsTool().invoke(
        DeviceToolContext(ref: ref, session: _session()),
        const {},
      ),
    );

    final actions = (out! as Map)['actions'] as List;
    expect(actions, hasLength(1));
    final action = actions.single as Map;
    expect(action['title'], 'Triage inbox actions');
    expect(action['project_title'], 'AI execution context');
    expect(action['commitment_title'], 'Weekly execution review');
  });

  test('summarize_execution_progress includes active rollup context', () async {
    final repo = ExecutionRepository(db: db, outbox: outbox);
    await repo.upsertProject(
      ExecutionProject(
        id: 'proj-context',
        title: 'ExecutionOS prod-basic',
        description: 'Make execution useful day to day.',
        horizon: ExecutionHorizon.month,
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(20),
      ),
    );
    await repo.upsertCommitment(
      ExecutionCommitment(
        id: 'commit-context',
        title: 'Friday review',
        projectId: 'proj-context',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(21),
      ),
    );
    await repo.upsertProgress(
      ExecutionProgressEntry(
        id: 'progress-context',
        projectId: 'proj-context',
        commitmentId: 'commit-context',
        kind: ExecutionProgressKind.checkin,
        note: 'Context is now visible to AI.',
        createdAt: DateTime.utc(2026, 6, 2),
        sync: _sync(22),
      ),
    );

    final out = await _withRef(
      container,
      (ref) => const SummarizeExecutionProgressTool().invoke(
        DeviceToolContext(ref: ref, session: _session()),
        const {'limit': 5},
      ),
    );

    final summary = out! as Map;
    expect(summary['active_project_count'], 1);
    expect(summary['active_commitment_count'], 1);
    final projects = summary['active_projects'] as List;
    final commitments = summary['active_commitments'] as List;
    final progress = summary['recent_progress'] as List;
    expect((projects.single as Map)['title'], 'ExecutionOS prod-basic');
    expect(
      (commitments.single as Map)['project_title'],
      'ExecutionOS prod-basic',
    );
    expect((progress.single as Map)['project_title'], 'ExecutionOS prod-basic');
    expect((progress.single as Map)['commitment_title'], 'Friday review');
  });
}
