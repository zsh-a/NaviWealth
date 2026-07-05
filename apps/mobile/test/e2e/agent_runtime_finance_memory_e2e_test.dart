import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';

import 'agent_runtime_e2e_support.dart';
import 'agent_runtime_long_task_scenario_harness.dart';

void main() {
  group('agent runtime FinanceOS long-task memory E2E', () {
    test('scenario advertises the cross-domain tool surface', () {
      const scenario = LongTaskFinanceMemoryScenario();
      final toolNames = [
        for (final tool in scenario.tools) tool['name'] as String,
      ];
      final toolsByName = <String, Map<String, Object?>>{
        for (final tool in scenario.tools) tool['name'] as String: tool,
      };

      expect(toolNames.toSet(), hasLength(toolNames.length));
      expect(
        toolNames,
        containsAll(<String>[
          'build_context',
          'remember_fact',
          'get_cashflow_buckets',
          'get_net_worth_summary',
          'list_payment_accounts',
          'propose_expense',
          'propose_project',
          'propose_action',
          'propose_progress',
          'propose_action_status_update',
          'propose_capture',
        ]),
      );
      expect(_toolDomain(toolsByName['propose_expense']), 'finance');
      expect(_toolDomain(toolsByName['propose_project']), 'execution');
      expect(_toolDomain(toolsByName['propose_capture']), 'knowledge');
    });

    test(
      'real LLM plans and replans with FinanceOS budget memory',
      () async {
        final config = RealLlmE2eConfig.fromEnvironment();
        if (!config.enabled) {
          // The test remains present in the suite while avoiding accidental
          // provider spend on normal developer and CI runs.
          // ignore: avoid_print
          print('Real LLM E2E not run: ${config.notEnabledReason}');
          return;
        }

        const scenario = LongTaskFinanceMemoryScenario();
        final dispatcher = ScenarioToolDispatcher();
        final runner = realLlmFrbChatRunner(
          config: config,
          tools: scenario.tools,
          dispatcher: dispatcher,
          agentId: kLongTaskE2eAgentId,
        );

        final day1 = await collectScenarioTurn(
          runner.runTurn(scenario.day1Request()),
          timeout: config.timeout,
          progress: ScenarioTurnProgressPrinter('day1').call,
        );
        _expectCompleted(day1);

        final day1ToolNames = dispatcher.calls
            .map((call) => call.name)
            .toList();
        expect(day1ToolNames, contains('build_context'));
        expect(day1ToolNames, contains('get_cashflow_buckets'));
        expect(day1ToolNames, contains('get_net_worth_summary'));
        expect(day1ToolNames, contains('list_payment_accounts'));
        expect(day1ToolNames, contains('propose_project'));
        expect(day1ToolNames, contains('propose_action'));
        expect(day1ToolNames, contains('remember_fact'));
        expect(dispatcher.projects, isNotEmpty);
        expect(dispatcher.actions.length, greaterThanOrEqualTo(2));
        expect(dispatcher.memories, isNotEmpty);
        expect(
          dispatcher.memoryCorpus.toLowerCase(),
          allOf(contains('80'), contains('2'), contains('wednesday')),
        );

        final callCountAfterDay1 = dispatcher.calls.length;
        final executionUpdatesAfterDay1 = dispatcher.executionUpdateCount;
        final day7 = await collectScenarioTurn(
          runner.runTurn(scenario.day7Request()),
          timeout: config.timeout,
          progress: ScenarioTurnProgressPrinter('day7').call,
        );
        _expectCompleted(day7);

        final day7ToolNames = dispatcher
            .callsSince(callCountAfterDay1)
            .map((call) => call.name)
            .toList();
        expect(day7ToolNames, contains('build_context'));
        expect(day7ToolNames, contains('get_cashflow_buckets'));
        expect(day7ToolNames, contains('propose_expense'));
        expect(
          day7ToolNames,
          anyOf(
            contains('propose_progress'),
            contains('propose_action_status_update'),
            contains('propose_action'),
          ),
        );
        expect(dispatcher.llmApiSpentUsd, closeTo(12.40, 0.01));
        expect(
          dispatcher.executionUpdateCount,
          greaterThan(executionUpdatesAfterDay1),
        );
        expect(dispatcher.memories.length, greaterThanOrEqualTo(2));
        expect(
          day7.text.toLowerCase(),
          anyOf(contains('budget'), contains('67.6'), contains('subagent')),
        );

        _expectNoSecretLeak(
          apiKey: config.apiKey,
          results: <ScenarioTurnResult>[day1, day7],
          dispatcher: dispatcher,
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });
}

String? _toolDomain(Map<String, Object?>? tool) {
  final metadata = tool?['metadata'];
  if (metadata is! Map) return null;
  final domain = metadata['domain'];
  return domain is String ? domain : null;
}

void _expectCompleted(ScenarioTurnResult result) {
  expect(result.errors, isEmpty, reason: result.diagnosticText());
  expect(result.done, isNotNull, reason: result.diagnosticText());
  expect(result.done!.stopReason, isNot('error'), reason: result.text);
  expect(
    result.spans.where((span) => span.kind == AiSpanKind.llm),
    isNotEmpty,
    reason: result.diagnosticText(),
  );
}

void _expectNoSecretLeak({
  required String apiKey,
  required List<ScenarioTurnResult> results,
  required ScenarioToolDispatcher dispatcher,
}) {
  final visibleArtifacts = <String>[
    for (final result in results) result.diagnosticText(),
    jsonEncode([
      for (final call in dispatcher.calls)
        <String, Object?>{'name': call.name, 'input': call.input},
    ]),
    jsonEncode([for (final memory in dispatcher.memories) memory.toWire()]),
  ].join('\n');
  if (visibleArtifacts.contains(apiKey)) {
    fail('Real LLM API key leaked into visible E2E artifacts');
  }
}
