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
import 'package:naviwealth/features/execution/ai_tools/propose_action_tool.dart';
import 'package:naviwealth/features/execution/ai_tools/propose_plan_tool.dart';
import 'package:naviwealth/features/execution/ai_tools/propose_progress_tool.dart';
import 'package:naviwealth/features/execution/ai_tools/summarize_execution_progress_tool.dart';
import 'package:naviwealth/features/execution/composition/execution_proposal_applier.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/execution/execution_ai_tools.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-exec-ai';
const _deviceId = 'dev-exec-ai';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late ProviderContainer container;

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        outboxStoreProvider.overrideWith((ref) async => outbox),
        currentUserIdProvider.overrideWithValue(() async => _userId),
        mutationStamperProvider.overrideWith((ref) async => _stamper()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('ExecutionOS exposes one plan proposal type', () async {
    final proposal = await _invoke(
      container,
      const ProposePlanTool(),
      const <String, Object?>{
        'title': 'Ship the release',
        'horizon': 'month',
        'reason': 'The outcome needs several actions',
      },
    ) as Map<Object?, Object?>;

    expect(proposal['kind'], 'execution_plan');
    expect(proposal['status'], 'ready');
    expect(
      kExecutionAssistantDeviceTools.map((tool) => tool.name),
      containsAll(<String>[
        'propose_action',
        'propose_plan',
        'propose_progress',
      ]),
    );
    expect(
      kExecutionAssistantDeviceTools.map((tool) => tool.name),
      isNot(contains('propose_commitment')),
    );
  });

  test(
    'proposal applier creates a plan, linked action, and progress',
    () async {
      final planState = await _apply(
        container,
        await _invoke(
          container,
          const ProposePlanTool(),
          const <String, Object?>{
            'title': 'Close ExecutionOS gaps',
            'horizon': 'month',
            'reason': 'The work is larger than one action',
          },
        ),
      );
      final repo = await container.read(executionRepositoryProvider.future);
      final plan = await repo.findPlan(
        ownerUserId: _userId,
        id: planState.appliedEntityId!,
      );
      expect(plan?.title, 'Close ExecutionOS gaps');
      expect(planState.appliedTable, 'execution_plans');

      final actionState = await _apply(
        container,
        await _invoke(container, const ProposeActionTool(), <String, Object?>{
          'title': 'Finish proposal coverage',
          'plan_id': plan!.id,
          'source_domain': 'finance',
          'source_row_family': 'fin:cashflow',
          'source_row_id': 'cashflow-2026-06',
          'reason': 'The plan needs a concrete next action',
        }),
      );
      final action = await repo.findAction(
        ownerUserId: _userId,
        id: actionState.appliedEntityId!,
      );
      expect(action?.planId, plan.id);
      expect(action?.source.rowFamily, 'fin:cashflow');

      final progressState = await _apply(
        container,
        await _invoke(container, const ProposeProgressTool(), <String, Object?>{
          'note': 'Proposal coverage is complete.',
          'kind': 'completion',
          'action_id': action!.id,
          'reason': 'Record the finished work',
        }),
      );
      final progress = await repo.findProgress(
        ownerUserId: _userId,
        id: progressState.appliedEntityId!,
      );
      expect(progress?.planId, plan.id);
      expect(progress?.actionId, action.id);
    },
  );

  test('read tools return plan-only execution context', () async {
    final repo = ExecutionRepository(db: db, outbox: outbox);
    await repo.upsertPlan(
      ExecutionPlan(
        id: 'plan-context',
        title: 'ExecutionOS release',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(1),
      ),
    );
    await repo.upsertAction(
      ExecutionAction(
        id: 'action-context',
        title: 'Triage actions',
        planId: 'plan-context',
        createdAt: DateTime.utc(2026, 6, 1),
        sync: _sync(2),
      ),
    );
    await repo.upsertProgress(
      ExecutionProgressEntry(
        id: 'progress-context',
        planId: 'plan-context',
        kind: ExecutionProgressKind.checkin,
        note: 'Context is visible.',
        createdAt: DateTime.utc(2026, 6, 2),
        sync: _sync(3),
      ),
    );

    final open = await _invoke(
      container,
      const ListOpenActionsTool(),
      const <String, Object?>{},
    ) as Map<Object?, Object?>;
    final action = (open['actions']! as List<Object?>).single! as Map;
    expect(action['plan_title'], 'ExecutionOS release');
    expect(action.containsKey('commitment_title'), isFalse);

    final summary = await _invoke(
      container,
      const SummarizeExecutionProgressTool(),
      const <String, Object?>{'limit': 5},
    ) as Map<Object?, Object?>;
    expect(summary['active_plan_count'], 1);
    expect(summary.containsKey('active_commitment_count'), isFalse);
    expect(summary['recent_progress'], hasLength(1));
  });
}

DeviceSession _session() => DeviceSession(messages: []);

Future<T> _withRef<T>(
  ProviderContainer container,
  Future<T> Function(Ref ref) body,
) {
  final probe = FutureProvider<T>((ref) => body(ref));
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}

Future<Object?> _invoke(
  ProviderContainer container,
  DeviceTool tool,
  Map<String, Object?> input,
) {
  return _withRef(
    container,
    (ref) =>
        tool.invoke(DeviceToolContext(ref: ref, session: _session()), input),
  );
}

Future<ProposalApplyState> _apply(
  ProviderContainer container,
  Object? proposal,
) {
  final plan = ProposalPlan.tryParse(proposal);
  expect(plan, isA<ReadyProposalPlan>());
  return _withRef(container, (ref) async {
    final applier = await ref.read(executionProposalApplierProvider.future);
    return applier.apply(plan! as ReadyProposalPlan);
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
    stampHlc: () async => _sync(tick++).hlc,
  );
}
