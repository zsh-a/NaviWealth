import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_execution.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';

import '../../persistence/test_database.dart';

AgentExecution _execution(String id, DateTime start, {String? process}) =>
    AgentExecution(
      runId: id,
      agentId: 'test',
      domain: 'finance',
      title: 'Review',
      instructions: 'Review facts',
      traceId: 'trace:$id',
      startedAt: start,
      processId: process ?? agentExecutionProcessId,
    );

void main() {
  test(
    'execution stream rechecks domain opt-ins and account changes',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      var owner = 'alice';
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWith(
            (_) =>
                () async => owner,
          ),
        ],
      );
      addTearDown(container.dispose);
      final start = DateTime.now().toUtc();
      final run = await SqliteAgentRunStore(db: db).acquireRun(
        ownerUserId: 'alice',
        agent: _Agent(),
        startedAt: start,
        trigger: AgentRunTrigger.manual,
      );
      final execution = _execution(run.record!.id, start);
      final json = execution.toJson()..['domain'] = 'health';
      await AgentExecutionStore(
        db,
        'alice',
      ).save(AgentExecution.fromJson(json));
      await container.read(domainOptInsProvider.future);
      await container
          .read(domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);
      final provider = agentExecutionProvider((
        agentId: 'test',
        runId: run.record!.id,
      ));
      container.listen(provider, (_, _) {});
      expect((await container.read(provider.future))?.title, 'Review');
      await container
          .read(domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, false);
      await container.pump();
      expect(await container.read(provider.future), isNull);
      await container
          .read(domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);
      await container.pump();
      expect(await container.read(provider.future), isNotNull);
      owner = 'bob';
      container.invalidate(currentUserIdProvider);
      await container.pump();
      expect(await container.read(provider.future), isNull);
    },
  );

  test(
    'projection is bounded, redacted and preserves independent progress',
    () {
      final execution = _execution('run', DateTime.now().toUtc());
      execution.record(
        const AiSpan(
          id: 'fast',
          kind: AiSpanKind.tool,
          name: 'tool:fast',
          startOffsetMs: 0,
          durationMs: 0,
          input: 'secret',
          output: 'secret',
          errorMessage: 'secret',
          attributes: {'secret': 'secret'},
        ),
        running: true,
      );
      execution.record(
        const AiSpan(
          id: 'slow',
          kind: AiSpanKind.tool,
          name: 'tool:slow',
          startOffsetMs: 0,
          durationMs: 0,
        ),
        running: true,
      );
      execution.record(
        const AiSpan(
          id: 'fast',
          kind: AiSpanKind.tool,
          name: 'tool:fast',
          startOffsetMs: 0,
          durationMs: 5,
        ),
      );
      final copy = AgentExecution.fromJson(execution.toJson());
      expect(copy.activeStepIds, {'slow'});
      expect(jsonEncode(copy.toJson()), isNot(contains('secret')));
      copy.status = 'cancelled';
      copy.closeActiveSteps();
      expect(copy.activeStepIds, isEmpty);
      expect(copy.steps.last.status, AiSpanStatus.cancelled);
      for (var i = 0; i < 100; i++) {
        copy.record(
          AiSpan(
            id: '$i',
            kind: AiSpanKind.tool,
            name: 'tool',
            startOffsetMs: 0,
            durationMs: 1,
          ),
          running: true,
        );
      }
      expect(copy.steps, hasLength(64));
      expect(copy.activeStepIds.length, lessThanOrEqualTo(64));
    },
  );

  test(
    'finishing a run preserves its projection and owner isolation',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final runs = SqliteAgentRunStore(db: db);
      final start = DateTime.now().toUtc();
      final acquired = await runs.acquireRun(
        ownerUserId: 'alice',
        agent: _Agent(),
        startedAt: start,
        trigger: AgentRunTrigger.manual,
      );
      final store = AgentExecutionStore(db, 'alice');
      final execution = _execution(acquired.record!.id, start)
        ..status = 'completed';
      await store.save(execution);
      await AgentExecutionStore(db, 'bob').save(execution..status = 'failed');
      await runs.finishRun(
        ownerUserId: 'alice',
        agent: _Agent(),
        runStartedAt: start,
        result: AgentRunResult(
          agentId: 'test',
          status: AgentRunStatus.completed,
          startedAt: start,
          finishedAt: start,
          summary: 'result',
        ),
        trigger: AgentRunTrigger.manual,
      );
      expect((await store.read('test'))?.traceId, execution.traceId);
      expect((await store.read('test'))?.status, 'completed');
      expect(await AgentExecutionStore(db, 'bob').read('test'), isNull);
      expect(
        (await runs.latestForAgent(
          ownerUserId: 'alice',
          agentId: 'test',
        ))?.traceId,
        execution.traceId,
      );
    },
  );

  test(
    'old-process execution is interrupted and releases the running lease',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final runs = SqliteAgentRunStore(db: db);
      final start = DateTime.now().toUtc();
      final acquired = await runs.acquireRun(
        ownerUserId: 'alice',
        agent: _Agent(),
        startedAt: start,
        trigger: AgentRunTrigger.manual,
      );
      final store = AgentExecutionStore(db, 'alice');
      await store.save(
        _execution(acquired.record!.id, start, process: 'previous-process'),
      );
      final recovered = await store.read('test');
      expect(recovered?.status, 'interrupted');
      expect(recovered?.errorCode, 'scheduled_task_interrupted');
      final next = await runs.acquireRun(
        ownerUserId: 'alice',
        agent: _Agent(),
        startedAt: start.add(const Duration(seconds: 1)),
        trigger: AgentRunTrigger.manual,
      );
      expect(next.acquired, isTrue);
      expect(
        (await store.read('test', runId: acquired.record!.id))?.status,
        'interrupted',
      );
    },
  );

  test('stop controls are scoped to owner and run', () {
    final controls = AgentExecutionControls();
    final token = CancelToken();
    controls.register('alice', 'run', token);
    controls.cancel('bob', 'run');
    expect(token.isCancelled, isFalse);
    controls.cancel('alice', 'run');
    expect(token.cancelError?.error, 'scheduled_task_user_cancelled');
    controls.dispose();
  });
}

class _Agent implements Agent {
  @override
  String get id => 'test';
  @override
  String get name => 'Test';
  @override
  AgentSchedule get schedule => AgentSchedule.everyHours(24);
  @override
  Future<AgentRunResult> run(AgentContext ctx) => throw UnimplementedError();
}
