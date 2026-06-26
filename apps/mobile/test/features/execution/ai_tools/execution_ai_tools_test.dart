import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:naviwealth/features/execution/composition/execution_proposal_applier.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

import '../../../core/persistence/test_database.dart';

const _userId = 'u-exec-ai';
const _deviceId = 'dev-exec-ai';

DeviceSession _session() => DeviceSession(messages: []);

Future<T> _withRef<T>(ProviderContainer c, Future<T> Function(Ref ref) body) {
  final probe = FutureProvider<T>((ref) => body(ref));
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
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

  test('execution proposal applier creates an action', () async {
    final proposal = await _withRef(
      container,
      (ref) => const ProposeActionTool()
          .invoke(DeviceToolContext(ref: ref, session: _session()), const {
            'title': 'Book Zone 2 workout',
            'reason': 'HealthOS recovery is good enough',
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
    expect(state.appliedTable, 'execution_actions');
  });

  test('list_open_actions reads repository-backed actions', () async {
    final repo = ExecutionRepository(db: db, outbox: outbox);
    await repo.upsertAction(
      ExecutionAction(
        id: 'a1',
        title: 'Triage inbox actions',
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
    expect((actions.single as Map)['title'], 'Triage inbox actions');
  });
}
