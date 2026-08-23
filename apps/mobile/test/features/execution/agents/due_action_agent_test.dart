import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/providers.dart' as agent_providers;
import 'package:naviwealth/core/ai/regression/agent_outcome_evaluator.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/agents/due_action_agent.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';

import '../../../core/persistence/test_database.dart';

const _owner = 'execution-due-owner';

void main() {
  late AppDatabase db;
  late ExecutionRepository repository;
  late SqliteAgentArtifactStore artifactStore;
  late ProviderContainer container;

  setUp(() {
    db = makeTestDatabase();
    repository = ExecutionRepository(db: db, outbox: InMemoryOutboxStore());
    artifactStore = SqliteAgentArtifactStore(db: db);
    container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(() async => _owner),
        executionRepositoryProvider.overrideWith((ref) async => repository),
        agent_providers.agentArtifactStoreProvider.overrideWith(
          (ref) async => artifactStore,
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('skips cleanly when no open action is due in the next day', () async {
    await repository.upsertAction(
      _action(
        id: 'later',
        title: 'Later action',
        dueAt: DateTime.utc(2026, 8, 3, 9),
      ),
    );

    final result = await _run(
      container,
      const ExecutionDueActionAgent(),
      DateTime.utc(2026, 8, 1, 8),
    );

    expect(result.status, AgentRunStatus.skipped);
    expect(result.artifactId, isNull);
    final failures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'execution.due_actions.no_finding',
      ),
      result: result,
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('creates a reminder artifact for open due actions only', () async {
    await repository.upsertAction(
      _action(
        id: 'due',
        title: 'File the report',
        dueAt: DateTime.utc(2026, 8, 2, 7),
      ),
    );
    await repository.upsertAction(
      _action(
        id: 'done',
        title: 'Already finished',
        dueAt: DateTime.utc(2026, 8, 1, 7),
        status: ExecutionActionStatus.done,
      ),
    );

    final result = await _run(
      container,
      const ExecutionDueActionAgent(),
      DateTime.utc(2026, 8, 1, 8),
    );
    final artifact = await artifactStore.read(result.artifactId!);

    expect(result.status, AgentRunStatus.completed);
    expect(result.payload['due_action_ids'], const <String>['due']);
    expect(artifact!.kind, AgentArtifactKind.reminder);
    expect(artifact.evidence.map((item) => item.id), const <String>['due']);
    expect(artifact.evidence.single.route, '/execution/action/due');
    final failures = evaluateAgentOutcomeCase(
      regressionCase: agentOutcomeRegressionCaseById(
        'execution.due_actions.ready',
      ),
      result: result,
      artifact: artifact,
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}

ExecutionAction _action({
  required String id,
  required String title,
  required DateTime dueAt,
  ExecutionActionStatus status = ExecutionActionStatus.todo,
}) {
  return ExecutionAction(
    id: id,
    title: title,
    dueAt: dueAt,
    status: status,
    completedAt: status == ExecutionActionStatus.done
        ? DateTime.utc(2026, 8, 1)
        : null,
    createdAt: DateTime.utc(2026, 7, 31),
    sync: SyncMeta(
      ownerUserId: _owner,
      updatedAt: DateTime.utc(2026, 7, 31),
      updatedByDevice: 'device',
      hlc: Hlc.zero('device'),
    ),
  );
}

Future<AgentRunResult> _run(
  ProviderContainer container,
  ExecutionDueActionAgent agent,
  DateTime now,
) {
  final probe = FutureProvider<AgentRunResult>(
    (ref) => agent.run(AgentContext(ref: ref, now: now)),
  );
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}
