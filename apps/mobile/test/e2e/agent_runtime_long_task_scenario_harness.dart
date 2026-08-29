import 'dart:convert';

import 'package:naviwealth/app/domain_packs/execution_pack.dart';
import 'package:naviwealth/app/domain_packs/finance_pack.dart';
import 'package:naviwealth/app/domain_packs/knowledge_pack.dart';
import 'package:naviwealth/core/ai/runtime/chat_agent.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';

import 'agent_runtime_e2e_support.dart';

const String kLongTaskE2eAgentId = 'long_task_finance_memory_e2e';
const String kLongTaskE2eSessionId = 'session_long_task_finance_memory_e2e';
const String kLongTaskE2eThreadId = 'thread_long_task_finance_memory_e2e';

final class LongTaskFinanceMemoryScenario {
  const LongTaskFinanceMemoryScenario();

  static const Set<String> _financeToolNames = <String>{
    'get_net_worth_summary',
    'get_cashflow_buckets',
    'list_payment_accounts',
    'propose_expense',
  };

  static const Set<String> _executionToolNames = <String>{
    'summarize_execution_progress',
    'list_open_actions',
    'propose_project',
    'propose_action',
    'propose_progress',
    'propose_action_status_update',
  };

  static const Set<String> _knowledgeToolNames = <String>{'propose_capture'};

  List<Map<String, Object?>> get tools => <Map<String, Object?>>[
    ..._memoryTools,
    ...domainPackE2eToolSpecs(
      packs: [kFinancePack, kExecutionPack, kKnowledgePack],
      selectedNames: <String>{
        ..._financeToolNames,
        ..._executionToolNames,
        ..._knowledgeToolNames,
      },
    ),
  ];

  List<Map<String, Object?>> get _memoryTools => <Map<String, Object?>>[
    e2eToolSpec(
      name: 'build_context',
      description:
          'Recall LifeOS memory before answering. Use it to recover prior '
          'constraints, decisions, budgets, and progress.',
      properties: const <String, Object?>{
        'query': <String, Object?>{'type': 'string'},
        'entities': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
      },
    ),
    e2eToolSpec(
      name: 'query_memory',
      description: 'Search the local LifeOS memory store.',
      required: const <String>['query'],
      properties: const <String, Object?>{
        'query': <String, Object?>{'type': 'string'},
      },
    ),
    e2eToolSpec(
      name: 'remember_fact',
      description:
          'Persist a durable LifeOS memory fact for this E2E task. Use this '
          'for constraints, budget facts, progress, and final review notes.',
      required: const <String>['title', 'summary'],
      risk: 'low',
      properties: const <String, Object?>{
        'title': <String, Object?>{'type': 'string'},
        'summary': <String, Object?>{'type': 'string'},
        'entities': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
      },
    ),
  ];

  ChatAgentTurnRequest day1Request() {
    return const ChatAgentTurnRequest(
      messages: <ChatAgentMessage>[
        ChatAgentMessage(role: 'system', content: _systemPrompt),
        ChatAgentMessage(
          role: 'user',
          content:
              'Day 1. I need to complete a general agent-runtime validation '
              'in 14 days. Total validation budget is 300 USD, LLM API budget '
              'is 80 USD, and the plan must not weaken my cash safety buffer. '
              'I can spend at most 2 hours per day and Wednesdays must stay '
              'light. Build the plan, create the execution proposals, and '
              'remember the constraints for future turns.',
        ),
      ],
      turnId: 'turn_day_1',
      sessionId: kLongTaskE2eSessionId,
      threadId: kLongTaskE2eThreadId,
      surface: 'agent_runtime_e2e',
      agentId: kLongTaskE2eAgentId,
      mode: 'long_task_finance_memory',
      temperature: 0,
      maxOutputTokens: 900,
      metadata: <String, Object?>{
        'scenario': 'finance_memory_long_task',
        'scenario_day': 1,
      },
    );
  }

  ChatAgentTurnRequest day7Request() {
    return const ChatAgentTurnRequest(
      messages: <ChatAgentMessage>[
        ChatAgentMessage(role: 'system', content: _systemPrompt),
        ChatAgentMessage(
          role: 'user',
          content:
              'Day 7. I finished the typed effect-loop case and the ChatTurn '
              'tool-resume case. Subagent validation is still incomplete. '
              'I also spent 12.40 USD on real OpenAI-compatible E2E calls. '
              'Using the remembered constraints and current FinanceOS budget, '
              'replan the remaining week and record the progress.',
        ),
      ],
      turnId: 'turn_day_7',
      sessionId: kLongTaskE2eSessionId,
      threadId: kLongTaskE2eThreadId,
      surface: 'agent_runtime_e2e',
      agentId: kLongTaskE2eAgentId,
      mode: 'long_task_finance_memory',
      temperature: 0,
      maxOutputTokens: 900,
      metadata: <String, Object?>{
        'scenario': 'finance_memory_long_task',
        'scenario_day': 7,
      },
    );
  }

  static const String _systemPrompt =
      'You are executing a NaviWealth automated E2E scenario. '
      'Do not answer from memory alone. Use tools for durable state and data. '
      'On Day 1, call build_context, get_cashflow_buckets, '
      'get_net_worth_summary, and list_payment_accounts before creating the '
      'plan. Then use propose_project with a reason, create at least two '
      'concrete propose_action entries with reasons, and remember_fact. '
      'On Day 7, call build_context and get_cashflow_buckets before replanning. '
      'Record the 12.40 USD LLM cost with propose_expense, update execution '
      'state with propose_progress or propose_action_status_update, and use '
      'remember_fact for the progress and remaining constraints. '
      'For LLM API expense, use currency USD and a note that mentions real '
      'LLM API E2E cost; use category other if no specific category fits. '
      'All writes must be proposed or remembered through tools.';
}

final class ScenarioToolCall {
  const ScenarioToolCall({required this.name, required this.input});

  final String name;
  final Map<String, Object?> input;
}

final class ScenarioMemoryFact {
  const ScenarioMemoryFact({
    required this.id,
    required this.title,
    required this.summary,
    required this.entities,
  });

  final String id;
  final String title;
  final String summary;
  final List<String> entities;

  Map<String, Object?> toWire() => <String, Object?>{
    'id': id,
    'kind': 'episodic',
    'title': title,
    'summary': summary,
    'entities': entities,
    'importance': 0.85,
    'confidence': 0.95,
  };
}

final class ScenarioToolDispatcher implements DeviceToolDispatcher {
  final calls = <ScenarioToolCall>[];
  final memories = <ScenarioMemoryFact>[];
  final expenses = <Map<String, Object?>>[];
  final projects = <Map<String, Object?>>[];
  final actions = <Map<String, Object?>>[];
  final progressEntries = <Map<String, Object?>>[];
  final statusUpdates = <Map<String, Object?>>[];
  final captures = <Map<String, Object?>>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    final object = _object(input);
    calls.add(ScenarioToolCall(name: name, input: object));
    return switch (name) {
      'build_context' => _buildContext(object),
      'query_memory' => _queryMemory(object),
      'remember_fact' => _rememberFact(object),
      'get_net_worth_summary' => _netWorthSummary(),
      'get_cashflow_buckets' => _cashflowBuckets(),
      'list_payment_accounts' => _paymentAccounts(),
      'propose_expense' => _proposeExpense(object),
      'summarize_execution_progress' => _executionSummary(),
      'list_open_actions' => <String, Object?>{'actions': _openActions()},
      'propose_project' => _proposeProject(object),
      'propose_action' => _proposeAction(object),
      'propose_progress' => _proposeProgress(object),
      'propose_action_status_update' => _proposeActionStatusUpdate(object),
      'propose_capture' => _proposeCapture(object),
      _ => <String, Object?>{
        'error': 'tool_unavailable',
        'code': 'tool_unavailable',
        'tool': name,
      },
    };
  }

  bool called(String name) => calls.any((call) => call.name == name);

  List<ScenarioToolCall> callsSince(int startIndex) {
    return calls.skip(startIndex).toList(growable: false);
  }

  double get llmApiSpentUsd {
    return expenses.fold<double>(0, (sum, expense) {
      final haystack =
          '${expense['category'] ?? ''} '
                  '${expense['merchant'] ?? ''} '
                  '${expense['memo'] ?? ''} '
                  '${expense['note'] ?? ''}'
              .toLowerCase();
      if (!haystack.contains('llm') &&
          !haystack.contains('api') &&
          !haystack.contains('openai')) {
        return sum;
      }
      return sum + _number(expense['amount']);
    });
  }

  int get executionUpdateCount => progressEntries.length + statusUpdates.length;

  String get memoryCorpus {
    return memories.map((m) => '${m.title}\n${m.summary}').join('\n');
  }

  Map<String, Object?> _buildContext(Map<String, Object?> input) {
    final query = '${input['query'] ?? ''}'.toLowerCase();
    final hits = _matchingMemories(query);
    return <String, Object?>{
      'user_preferences': const <Object?>[],
      'applicable_rules': hits.map((m) => m.toWire()).toList(growable: false),
      'related_decisions': const <Object?>[],
      'recent_events': progressEntries,
      'related_events': hits.map((m) => m.toWire()).toList(growable: false),
      if (hits.isEmpty)
        'guidance': 'No remembered constraints yet; inspect FinanceOS tools.',
    };
  }

  Map<String, Object?> _queryMemory(Map<String, Object?> input) {
    final query = '${input['query'] ?? ''}'.toLowerCase();
    final hits = _matchingMemories(query)
        .map((m) => <String, Object?>{...m.toWire(), 'score': 0.91})
        .toList(growable: false);
    return <String, Object?>{
      'hits': hits,
      'memory_size': memories.length,
      if (hits.isEmpty) 'guidance': 'No matching memory facts.',
    };
  }

  List<ScenarioMemoryFact> _matchingMemories(String query) {
    if (query.trim().isEmpty) return memories.toList(growable: false);
    final tokens = query
        .split(RegExp(r'[^a-z0-9_.-]+'))
        .where((token) => token.length >= 3)
        .toList(growable: false);
    if (tokens.isEmpty) return memories.toList(growable: false);
    return memories
        .where((memory) {
          final haystack =
              '${memory.title}\n${memory.summary}\n${memory.entities.join(' ')}'
                  .toLowerCase();
          return tokens.any(haystack.contains);
        })
        .toList(growable: false);
  }

  Map<String, Object?> _rememberFact(Map<String, Object?> input) {
    final id = 'memory_${memories.length + 1}';
    final title = _string(input['title'], fallback: 'Runtime validation fact');
    final summary = _string(input['summary'], fallback: jsonEncode(input));
    final fact = ScenarioMemoryFact(
      id: id,
      title: title,
      summary: summary,
      entities: _stringList(input['entities']),
    );
    memories.add(fact);
    return <String, Object?>{
      'memory_id': id,
      'memory_size': memories.length,
      'memory': fact.toWire(),
    };
  }

  Map<String, Object?> _netWorthSummary() => const <String, Object?>{
    'base_currency': 'USD',
    'net_worth': 125000,
    'liquid_cash': 18400,
    'cash_safety_months': 6.2,
    'safe_to_spend_usd': 300,
    'guidance': 'Validation spending must keep cash safety above 6 months.',
  };

  Map<String, Object?> _cashflowBuckets() {
    final remaining = (80 - llmApiSpentUsd).clamp(0, 80);
    return <String, Object?>{
      'currency': 'USD',
      'monthly_discretionary_remaining': 640,
      'validation_budget_usd': 300,
      'llm_api_budget_usd': 80,
      'llm_api_spent_usd': llmApiSpentUsd,
      'llm_api_remaining_usd': remaining,
      'cash_safety_months_after_budget': 6.1,
      'buckets': <Object?>[
        <String, Object?>{
          'id': 'validation',
          'label': 'Agent runtime validation',
          'budget_usd': 300,
          'spent_usd': llmApiSpentUsd,
        },
        <String, Object?>{
          'id': 'llm_api',
          'label': 'Real LLM API calls',
          'budget_usd': 80,
          'spent_usd': llmApiSpentUsd,
        },
      ],
    };
  }

  Map<String, Object?> _paymentAccounts() => const <String, Object?>{
    'accounts': <Object?>[
      <String, Object?>{
        'id': 'acct_checking_usd',
        'name': 'Checking USD',
        'currency': 'USD',
        'available': 18400,
        'purpose': 'expense',
      },
    ],
  };

  Map<String, Object?> _proposeExpense(Map<String, Object?> input) {
    final amount = _number(input['amount'] ?? input['amount_usd']);
    final note = _string(
      input['note'] ?? input['memo'],
      fallback: 'Real LLM E2E API cost',
    );
    final expense = <String, Object?>{
      'id': 'expense_${expenses.length + 1}',
      'amount': amount,
      'currency': _string(input['currency'], fallback: 'USD'),
      'merchant': _string(input['merchant'], fallback: 'LLM provider'),
      'category': _string(input['category'], fallback: 'llm_api'),
      'account_id': _string(input['account_id'], fallback: 'acct_checking_usd'),
      'memo': note,
      'note': note,
    };
    expenses.add(expense);
    return _readyProposal(
      id: 'proposal_finance_expense_${expenses.length}',
      kind: 'expense',
      summary: 'Record ${expense['amount']} ${expense['currency']} LLM cost',
      payload: expense,
    );
  }

  Map<String, Object?> _executionSummary() => <String, Object?>{
    'projects': projects,
    'open_actions': _openActions(),
    'progress': progressEntries,
    'status_updates': statusUpdates,
  };

  List<Map<String, Object?>> _openActions() {
    return actions
        .where((action) => action['status'] != 'done')
        .toList(growable: false);
  }

  Map<String, Object?> _proposeProject(Map<String, Object?> input) {
    final project = <String, Object?>{
      'id': _string(input['id'], fallback: 'project_${projects.length + 1}'),
      'title': _string(input['title'], fallback: 'Agent runtime validation'),
      'summary': _string(
        input['description'] ?? input['summary'],
        fallback: '',
      ),
      'target_date': _string(
        input['target_date'] ?? input['due_date'],
        fallback: '2026-07-19',
      ),
      'horizon': _string(input['horizon'], fallback: 'week'),
      'reason': _string(input['reason'], fallback: 'Long-task validation plan'),
      'status': 'active',
    };
    projects.add(project);
    return _readyProposal(
      id: 'proposal_execution_plan_${projects.length}',
      kind: 'execution_plan',
      summary: 'Create project ${project['title']}',
      payload: project,
    );
  }

  Map<String, Object?> _proposeAction(Map<String, Object?> input) {
    final action = <String, Object?>{
      'id': _string(input['id'], fallback: 'action_${actions.length + 1}'),
      'title': _string(input['title'], fallback: 'Runtime validation action'),
      'plan_id': _string(
        input['plan_id'],
        fallback: projects.isEmpty ? 'project_1' : '${projects.last['id']}',
      ),
      'due_at': _string(input['due_at'] ?? input['due_date'], fallback: ''),
      'scheduled_for': _string(input['scheduled_for'], fallback: ''),
      'estimate_minutes': _int(input['estimate_minutes'], fallback: 120),
      'priority': _string(input['priority'], fallback: 'normal'),
      'note': _string(input['note'], fallback: ''),
      'reason': _string(input['reason'], fallback: 'Runtime validation step'),
      'status': 'open',
    };
    actions.add(action);
    return _readyProposal(
      id: 'proposal_execution_action_${actions.length}',
      kind: 'execution_action',
      summary: 'Create action ${action['title']}',
      payload: action,
    );
  }

  Map<String, Object?> _proposeProgress(Map<String, Object?> input) {
    final progress = <String, Object?>{
      'id': 'progress_${progressEntries.length + 1}',
      'plan_id': _string(input['plan_id'], fallback: 'project_1'),
      'action_id': _string(input['action_id'], fallback: ''),
      'note': _string(input['note'], fallback: jsonEncode(input)),
      'kind': _string(input['kind'], fallback: 'checkin'),
      'reason': _string(input['reason'], fallback: 'Runtime validation update'),
    };
    progressEntries.add(progress);
    return _readyProposal(
      id: 'proposal_execution_progress_${progressEntries.length}',
      kind: 'execution_progress',
      summary: 'Record progress',
      payload: progress,
    );
  }

  Map<String, Object?> _proposeActionStatusUpdate(Map<String, Object?> input) {
    final actionId = _string(input['action_id'], fallback: '');
    final status = _string(input['status'], fallback: 'blocked');
    final note = _string(input['progress_note'] ?? input['note'], fallback: '');
    final update = <String, Object?>{
      'id': 'status_update_${statusUpdates.length + 1}',
      'action_id': actionId,
      'status': status,
      'progress_note': note,
      'reason': _string(
        input['reason'],
        fallback: 'Runtime validation status update',
      ),
    };
    statusUpdates.add(update);
    for (final action in actions) {
      if (action['id'] == actionId) {
        action['status'] = status;
        action['status_note'] = note;
      }
    }
    return _readyProposal(
      id: 'proposal_execution_status_${statusUpdates.length}',
      kind: 'execution_action_status_update',
      summary: 'Update action $actionId to $status',
      payload: update,
    );
  }

  Map<String, Object?> _proposeCapture(Map<String, Object?> input) {
    final capture = <String, Object?>{
      'id': 'capture_${captures.length + 1}',
      'kind': _string(input['kind'], fallback: 'note'),
      'text': _string(input['text'], fallback: jsonEncode(input)),
      'tags': _stringList(input['tags']),
    };
    captures.add(capture);
    return _readyProposal(
      id: 'proposal_knowledge_capture_${captures.length}',
      kind: 'knowledge_capture',
      summary: 'Capture validation knowledge',
      payload: capture,
    );
  }
}

Map<String, Object?> _readyProposal({
  required String id,
  required String kind,
  required String summary,
  required Map<String, Object?> payload,
}) {
  return <String, Object?>{
    'proposal_id': id,
    'kind': kind,
    'status': 'ready',
    'summary': summary,
    'payload': payload,
  };
}

Map<String, Object?> _object(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

String _string(Object? value, {required String fallback}) {
  return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

double _number(Object? value) {
  return switch (value) {
    num v => v.toDouble(),
    String v => double.tryParse(v) ?? _firstNumber(v),
    _ => 0,
  };
}

double _firstNumber(String value) {
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
  if (match == null) return 0;
  return double.tryParse(match.group(0) ?? '') ?? 0;
}

int _int(Object? value, {required int fallback}) {
  return switch (value) {
    int v => v,
    num v => v.toInt(),
    String v => int.tryParse(v) ?? fallback,
    _ => fallback,
  };
}
