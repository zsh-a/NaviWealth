import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_stream_bridge.dart';
import 'package:naviwealth/app/agents/scheduled_agent_composition.dart';
import 'package:naviwealth/app/agents/scheduled_llm_executor.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_execution.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/agents/providers.dart';
import 'package:naviwealth/core/ai/agents/scheduled_agent_store.dart';
import 'package:naviwealth/core/ai/agents/scheduled_agent_task.dart';
import 'package:naviwealth/core/ai/agents/scheduled_task_applier.dart';
import 'package:naviwealth/core/ai/composition/device_tools_provider.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/ai/composition/tool_descriptor_lookup.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/chat_agent.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/propose_scheduled_task_tool.dart';
import 'package:naviwealth/core/ai/trace/providers.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/test_database.dart';

class _Tool implements DeviceTool {
  _Tool(this.name);
  @override
  final String name;
  int calls = 0;
  @override
  String get description => name;
  @override
  Map<String, Object?> get inputSchema => {'type': 'object'};
  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    calls++;
    return {'value': 123, 'unit': 'CNY'};
  }
}

class _Chat implements ChatAgent {
  _Chat(this.handler, {this.invalidEvidence = false});
  final Future<String> Function(String) handler;
  final bool invalidEvidence;
  @override
  Stream<AiChatEvent> runTurn(ChatAgentTurnRequest request) async* {
    expect(
      request.messages.first.content,
      contains('Write summary as readable Markdown'),
    );
    expect(
      request.messages.first.content,
      contains('outer response must remain valid JSON'),
    );
    // Model work is runner-owned: losing focus or hiding a window must not
    // cancel the live turn or prevent its subsequent tool dispatch.
    final binding = WidgetsBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(request.cancelToken?.isCancelled, isFalse);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final denied = jsonDecode(
      await handler(
        jsonEncode({
          'id': 'bad',
          'method': 'tool.call',
          'params': {'name': 'write', 'input': <String, Object?>{}},
        }),
      ),
    ) as Map;
    expect((denied['outcome'] as Map)['status'], 'policy_denied');
    final result = jsonDecode(
      await handler(
        jsonEncode({
          'id': 'read',
          'method': 'tool.call',
          'params': {'name': 'read', 'input': <String, Object?>{}},
        }),
      ),
    ) as Map;
    expect((result['result'] as Map)['evidence_id'], 'e1');
    yield TextEvent(
      jsonEncode({
        'summary': _markdownReport,
        'evidence_ids': [invalidEvidence ? 'invented' : 'e1'],
      }),
    );
    yield const DoneEvent(stopReason: 'end_turn', rounds: 2);
  }
}

class _LegacyAgent implements Agent {
  _LegacyAgent(this.id);
  @override
  final String id;
  int calls = 0;
  @override
  String get name => id;
  @override
  AgentSchedule get schedule => AgentSchedule.everyHours(24);
  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    calls++;
    throw StateError('legacy path must never execute');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final verbose in [false, true]) {
    for (final code in [
      'provider_auth_error',
      'scheduled_task_user_cancelled',
      'scheduled_task_backgrounded',
      'model_unavailable',
    ]) {
      test('persistent execution retains $code and capture=$verbose', () async {
        SharedPreferences.setMockInitialValues({
          'naviwealth.ai.trace_verbose': verbose,
        });
        final db = makeTestDatabase();
        addTearDown(db.close);
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWith((_) async => db),
            currentUserIdProvider.overrideWithValue(() async => 'alice'),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            deviceToolsProvider.overrideWithValue([_Tool('read')]),
            toolDescriptorLookupProvider.overrideWithValue(
              (name) => ToolDescriptor(
                name: name,
                domain: 'finance',
                access: Access.read,
                risk: RiskLevel.info,
                requiresConfirmation: Confirmation.none,
                allowedContextTier: BudgetTier.small,
              ),
            ),
            scheduledChatBuilderProvider.overrideWithValue((
              id,
              tools,
              handler,
            ) {
              if (code == 'model_unavailable') {
                throw ScheduledExecutionFailure(code, 'Missing model');
              }
              return _FailureChat(code);
            }),
          ],
        );
        addTearDown(container.dispose);
        final task = ScheduledAgentTask(
          id: 'weekly_wealth_review',
          title: 'Review',
          instructions: 'Read facts',
          domain: DomainScope.finance,
          schedule: const AgentSchedule.weekly(weekday: 7, hour: 20),
          createdAt: DateTime.now(),
        );
        final agent = ScheduledLlmAgent(task, executeScheduledLlmTask);
        final start = DateTime.now().toUtc();
        final runs = SqliteAgentRunStore(db: db);
        final acquired = await runs.acquireRun(
          ownerUserId: 'alice',
          agent: agent,
          startedAt: start,
          trigger: AgentRunTrigger.manual,
        );
        final provider = FutureProvider(
          (ref) => agent.run(
            AgentContext(ref: ref, now: start, runId: acquired.record!.id),
          ),
        );
        final result = await container.read(provider.future);
        expect(result.status, AgentRunStatus.failed);
        expect(result.error, code);
        await runs.finishRun(
          ownerUserId: 'alice',
          agent: agent,
          runStartedAt: start,
          result: result,
          trigger: AgentRunTrigger.manual,
        );
        final execution = await AgentExecutionStore(db, 'alice').read(task.id);
        expect(execution?.errorCode, code);
        expect(execution?.activeStepIds, isEmpty);
        expect(
          execution?.status,
          code == 'scheduled_task_user_cancelled'
              ? 'cancelled'
              : code == 'scheduled_task_backgrounded'
              ? 'interrupted'
              : 'failed',
        );
        expect(execution?.summary, isNull);
        expect(
          execution!.steps.every(
            (span) => span.input == null && span.output == null,
          ),
          isTrue,
        );
        final trace = await container
            .read(aiTraceStoreProvider)
            .findByRequestId(execution.traceId);
        expect(trace, isNotNull);
        if (code != 'model_unavailable') {
          final steps = trace!.spans.where(
            (span) => span.kind != AiSpanKind.turn,
          );
          expect(steps, hasLength(2));
          for (final span in steps) {
            expect(span.input, verbose ? {'request': 'debug input'} : null);
            expect(span.output, verbose ? 'debug output' : null);
          }
        }
      });
    }
  }
  for (final domain in [DomainScope.finance, DomainScope.health]) {
    test(
      'built-in $domain review uses LLM and never falls back without a model',
      () async {
        SharedPreferences.setMockInitialValues({});
        final db = makeTestDatabase();
        addTearDown(db.close);
        await DomainOptInStore(db)
            .write(DomainOptIns({DomainScope.finance, DomainScope.health}));
        final read = _Tool('read');
        final legacy = _LegacyAgent(
          domain == DomainScope.finance
              ? 'weekly_wealth_review'
              : 'weekly_summary',
        );
        final c = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWith((_) async => db),
            currentUserIdProvider.overrideWithValue(() async => 'alice'),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            agentRuntimeLlmStreamBridgeProvider.overrideWithValue(null),
            deviceToolsProvider.overrideWithValue([read]),
            toolDescriptorLookupProvider.overrideWithValue(
              (name) => ToolDescriptor(
                name: name,
                domain: domain.wire,
                access: Access.read,
                risk: RiskLevel.info,
                requiresConfirmation: Confirmation.none,
                allowedContextTier: BudgetTier.small,
              ),
            ),
          ],
        );
        addTearDown(c.dispose);
        await c.read(scheduledAgentTasksProvider.future);
        final p = FutureProvider((ref) {
          final agent = composeScheduledAgents(ref, [
            DomainAgentRegistration(agent: legacy, domain: domain),
          ]).single.agent;
          expect(agent, isA<ScheduledLlmAgent>());
          expect(agent.id, legacy.id);
          expect(agent.schedule.weekdayLocal, DateTime.sunday);
          return agent.run(AgentContext(ref: ref, now: DateTime.now().toUtc()));
        });
        await expectLater(c.read(p.future), throwsStateError);
        expect(legacy.calls, 0);
        expect(read.calls, 0);
      },
    );
  }
  for (final invalid in [false, true]) {
    test(
      'LLM execution enforces read-only registry and evidence (invalid=$invalid)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = makeTestDatabase();
        addTearDown(db.close);
        final read = _Tool('read');
        final write = _Tool('write');
        final other = _Tool('other_domain');
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWith((_) async => db),
            currentUserIdProvider.overrideWithValue(() async => 'alice'),
            sharedPreferencesProvider.overrideWithValue(prefs),
            deviceToolsProvider.overrideWithValue([read, write, other]),
            toolDescriptorLookupProvider.overrideWithValue(
              (name) => ToolDescriptor(
                name: name,
                domain: name == 'other_domain' ? 'health' : 'finance',
                access: name == 'write' ? Access.propose : Access.read,
                risk: RiskLevel.info,
                requiresConfirmation: Confirmation.none,
                allowedContextTier: BudgetTier.small,
              ),
            ),
            scheduledChatBuilderProvider.overrideWithValue((
              id,
              tools,
              handler,
            ) {
              expect(tools.map((tool) => tool['name']), ['read']);
              return _Chat(handler, invalidEvidence: invalid);
            }),
          ],
        );
        addTearDown(container.dispose);
        final task = ScheduledAgentTask(
          id: 'user_task:test',
          title: 'Report',
          instructions: 'Review facts',
          domain: DomainScope.finance,
          schedule: const AgentSchedule.weekly(weekday: 7, hour: 20),
          createdAt: DateTime.now(),
        );
        await (await container.read(scheduledAgentStoreProvider.future))
            .save(task, expectedRevision: 0);
        final provider = FutureProvider(
          (ref) => executeScheduledLlmTask(
            task,
            AgentContext(ref: ref, now: DateTime.now().toUtc()),
          ),
        );
        if (invalid) {
          await expectLater(container.read(provider.future), throwsStateError);
        } else {
          final result = await container.read(provider.future);
          expect(result.status, AgentRunStatus.completed);
          expect(result.payload['source'], 'llm');
          final artifact = await (await container.read(
            agentArtifactStoreProvider.future,
          )).read(result.artifactId!);
          expect(artifact!.evidence.single.label, 'read');
          expect(artifact.summary, _markdownReport);
          expect(result.summary, _markdownReport);
          expect(artifact.traceId, isNotNull);
        }
        expect(read.calls, 1);
        expect(write.calls, 0);
        expect(other.calls, 0);
      },
    );
  }

  test(
    'conversation proposal does not schedule until confirmed; undo disables',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = makeTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'alice'),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final tool = FutureProvider(
        (ref) => const ProposeScheduledTaskTool().invoke(
          DeviceToolContext(ref: ref, session: const DeviceToolSession()),
          {
            'title': 'Weekly review',
            'instructions': 'Review finances',
            'domain': 'finance',
            'weekday': 7,
            'hour': 20,
            'minute': 0,
          },
        ),
      );
      final plan = ProposalPlan.tryParse(
        await container.read(tool.future),
      ) as ReadyProposalPlan;
      final store = await container.read(scheduledAgentStoreProvider.future);
      expect(await store.list(), isEmpty);
      final applier = Provider((ref) => ScheduledTaskApplier(ref));
      final state = await container.read(applier).apply(plan);
      expect(state.status, ProposalApplyStatus.applied);
      expect((await store.list()).single.id, state.appliedEntityId);
      await expectLater(container.read(applier).apply(plan), throwsException);
      await container.read(applier).undo(state);
      expect(
        await (await container.read(agentPreferenceStoreProvider.future))
            .isEnabled(ownerUserId: 'alice', agentId: state.appliedEntityId!),
        false,
      );
    },
  );
}

const _markdownReport =
    '**Overview**\n\nBased on available data.\n\n'
    '## Findings\n\n- Read the current facts.\n\n'
    '## Limitations\n\nHistorical comparisons are unavailable.';

class _FailureChat implements ChatAgent {
  _FailureChat(this.code);
  final String code;
  @override
  Stream<AiChatEvent> runTurn(ChatAgentTurnRequest request) async* {
    for (final kind in [AiSpanKind.llm, AiSpanKind.tool]) {
      final now = DateTime.now().toUtc();
      yield SpanEvent(
        id: kind.name,
        kind: kind,
        name: kind.name,
        startedAt: now,
        endedAt: now,
        input: const {'request': 'debug input'},
        output: 'debug output',
      );
    }
    if (code.startsWith('scheduled_task_')) {
      request.cancelToken!.cancel(code);
      yield const DoneEvent(stopReason: 'cancelled', rounds: 1);
    } else {
      yield ErrorEvent('Provider details must not become UI text', code: code);
    }
  }
}
