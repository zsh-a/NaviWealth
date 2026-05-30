import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';

void main() {
  group('ContextPack roundtrip', () {
    test('fully populated pack round-trips through JSON', () {
      final pack = _samplePack();
      final encoded = jsonEncode(pack.toJson());
      final decoded = ContextPack.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );

      expect(decoded.version.major, pack.version.major);
      expect(decoded.version.minor, pack.version.minor);
      expect(decoded.budget.tier, pack.budget.tier);

      expect(decoded.base.preferredCurrency, pack.base.preferredCurrency);
      expect(decoded.base.riskPreference, pack.base.riskPreference);
      expect(decoded.base.accounts.totalCount, pack.base.accounts.totalCount);
      expect(decoded.base.accounts.byKind, pack.base.accounts.byKind);
      expect(decoded.base.cashflow.trend, pack.base.cashflow.trend);
      expect(
        decoded.base.cashflow.averageOutflowMinor,
        pack.base.cashflow.averageOutflowMinor,
      );
      expect(decoded.base.fireGoal?.currency, pack.base.fireGoal?.currency);
      expect(
        decoded.base.fireGoal?.progressFraction,
        pack.base.fireGoal?.progressFraction,
      );

      expect(decoded.task.route.area, pack.task.route.area);
      expect(decoded.task.intent.capability, pack.task.intent.capability);
      expect(decoded.task.intent.risk, pack.task.intent.risk);
      expect(decoded.task.intent.label, pack.task.intent.label);
      expect(decoded.task.signals, hasLength(pack.task.signals.length));
      expect(decoded.task.signals.first.kind, pack.task.signals.first.kind);
    });

    test('snake_case wire keys are stable', () {
      final json = _samplePack().toJson();
      // Spot-check that we never accidentally emit camelCase. The Rust
      // mirror uses serde rename_all = "snake_case" — drift between
      // sides shows up as wire incompatibility, so this is the cheapest
      // canary.
      expect(json.containsKey('version'), isTrue);
      expect(json.containsKey('base'), isTrue);
      final base = json['base']! as Map<String, Object?>;
      expect(base.containsKey('preferred_currency'), isTrue);
      expect(base.containsKey('risk_preference'), isTrue);
      final cashflow = base['cashflow']! as Map<String, Object?>;
      expect(cashflow.containsKey('months_covered'), isTrue);
      expect(cashflow.containsKey('average_inflow_minor'), isTrue);
      expect(cashflow.containsKey('average_outflow_minor'), isTrue);
      final task = json['task']! as Map<String, Object?>;
      final intent = task['intent']! as Map<String, Object?>;
      expect(intent['capability'], 'analyze');
      expect(intent['risk'], 'suggest');
    });

    test('unknown enum values fall through to safe defaults', () {
      final raw = <String, Object?>{
        'version': <String, Object?>{'major': 1, 'minor': 0},
        'base': <String, Object?>{
          'preferred_currency': 'USD',
          'risk_preference': 'extreme', // not a real value
          'accounts': <String, Object?>{
            'total_count': 0,
            'by_kind': <String, Object?>{},
          },
          'cashflow': <String, Object?>{
            'base_currency': 'USD',
            'months_covered': 0,
            'average_inflow_minor': '0',
            'average_outflow_minor': '0',
            'trend': 'sideways', // not a real value
          },
        },
        'task': <String, Object?>{
          'route': <String, Object?>{'path': '/', 'area': 'unknown'},
          'intent': <String, Object?>{
            'capability': 'time_travel', // not a real value
            'risk': 'whatever',
          },
        },
        'budget': <String, Object?>{'tier': 'unbounded'},
      };
      final pack = ContextPack.fromJson(raw);
      expect(pack.base.riskPreference, RiskPreference.moderate);
      expect(pack.base.cashflow.trend, CashflowTrend.unknown);
      expect(pack.task.intent.capability, Capability.analyze);
      expect(pack.task.intent.risk, RiskLevel.info);
      expect(pack.budget.tier, BudgetTier.standard);
    });

    test('byte caps are 4KB / 16KB / 64KB', () {
      expect(BudgetTier.small.byteCap, 4 * 1024);
      expect(BudgetTier.standard.byteCap, 16 * 1024);
      expect(BudgetTier.large.byteCap, 64 * 1024);
    });

    test('assertBudget passes when within cap', () {
      final pack = _samplePack();
      // Sample pack is ~1KB — well within standard's 16KB cap.
      expect(pack.serializedByteSize, lessThan(BudgetTier.standard.byteCap));
      expect(() => pack.assertBudget(), returnsNormally);
    });

    test('assertBudget throws when oversize for tier', () {
      // Force oversize by stuffing many signals into a small-tier pack.
      final fatTask = TaskContext(
        route: const RouteContext(path: '/expense', area: 'expense'),
        intent: const IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
        signals: List<RecentSignal>.generate(
          200,
          (i) => RecentSignal(
            kind: SignalKind.spendingSpike,
            severity: SignalSeverity.warn,
            summaryZh: '触发了一条相当长的提示文案以撑大序列化体积 #$i',
          ),
          growable: false,
        ),
      );
      final pack = ContextPack(
        version: kCurrentContextPackVersion,
        base: _sampleBase(),
        task: fatTask,
        budget: PrivacyBudget.small,
      );
      expect(
        () => pack.assertBudget(),
        throwsA(isA<ContextPackOversizeException>()),
      );
    });
  });

  group('ToolDescriptor roundtrip', () {
    test('descriptor round-trips with all axes', () {
      const desc = ToolDescriptor(
        name: 'request_disclosure',
        access: Access.read,
        risk: RiskLevel.info,
        requiresConfirmation: Confirmation.oneTap,
        allowedContextTier: BudgetTier.standard,
      );
      final decoded = ToolDescriptor.fromJson(
        jsonDecode(jsonEncode(desc.toJson())) as Map<String, Object?>,
      );
      expect(decoded.name, desc.name);
      expect(decoded.access, desc.access);
      expect(decoded.risk, desc.risk);
      expect(decoded.requiresConfirmation, desc.requiresConfirmation);
      expect(decoded.allowedContextTier, desc.allowedContextTier);
    });

    test('mobile descriptor catalog carries active device tools', () {
      // 3 shell (query_memory, build_context, ask_user) + 35 FinanceOS +
      // 5 HealthOS + 16 KnowledgeOS = 59. `ask_user` is the structured
      // decision-point tool (Claude-Code-style interactive choices). Each
      // LifeOS domain co-locates its descriptors with its tool barrel
      // (`kShellToolDescriptors`, `kFinanceToolDescriptors`,
      // `kHealthToolDescriptors`, `kKnowledgeToolDescriptors`); the union
      // here is derived in `tool_descriptor_catalog.dart`.
      expect(allToolDescriptors, hasLength(59));
      expect(
        lookupToolDescriptor('propose_options_profile_update')?.sideEffect,
        SideEffect.deviceLocalWrite,
      );
      expect(
        lookupToolDescriptor('list_payment_accounts')?.allowedContextTier,
        BudgetTier.standard,
      );
      expect(
        lookupToolDescriptor('propose_expense')?.sideEffect,
        SideEffect.deviceLocalWrite,
      );
      expect(lookupToolDescriptor('get_journal_entries'), isNull);
    });

    // Regression — 2026-05-24 boundary audit removed `allowed_runtimes`,
    // `read_model_layer`, and `used_cloud` from ToolDescriptor's wire
    // shape. Silent re-introduction would mean drift back toward the
    // multi-runtime / freshness-gated design we deliberately deleted.
    // D-1.3 added `domain` so the catalog can partition shell vs
    // finance tools — bumping the canonical key count from 6 → 7.
    test('toJson emits exactly the seven documented keys', () {
      const desc = ToolDescriptor(
        name: 'sentinel',
        access: Access.read,
        risk: RiskLevel.info,
        requiresConfirmation: Confirmation.none,
        allowedContextTier: BudgetTier.small,
      );
      final keys = desc.toJson().keys.toSet();
      expect(keys, <String>{
        'name',
        'access',
        'risk',
        'requires_confirmation',
        'allowed_context_tier',
        'side_effect',
        'domain',
      });
    });

    test('fromJson tolerates removed legacy keys', () {
      // Persisted ToolDescriptor JSON from before the boundary audit
      // would carry these fields. Decoding must succeed and the new
      // fields must take their documented defaults.
      final legacy = <String, Object?>{
        'name': 'legacy_tool',
        'access': 'read',
        'risk': 'info',
        'requires_confirmation': 'none',
        'allowed_context_tier': 'small',
        'allowed_runtimes': <String>['device', 'cloud'],
        'read_model_layer': 'analytics',
        'used_cloud': true,
      };
      final decoded = ToolDescriptor.fromJson(legacy);
      expect(decoded.name, 'legacy_tool');
      expect(decoded.sideEffect, SideEffect.none);
    });

    test('every propose_* descriptor is a deviceLocalWrite', () {
      // §4.5 invariant: confirmation-gated proposals are local writes.
      // A propose_* with sideEffect=none would bypass the confirm flow
      // typing; a propose_* with externalCall would be unreachable.
      final proposals = allToolDescriptors.where(
        (d) => d.name.startsWith('propose_'),
      );
      expect(proposals, isNotEmpty);
      for (final d in proposals) {
        expect(
          d.sideEffect,
          SideEffect.deviceLocalWrite,
          reason: '${d.name} must be deviceLocalWrite (§4.5)',
        );
        expect(
          d.access,
          Access.propose,
          reason: '${d.name} must have access=propose',
        );
        expect(
          d.requiresConfirmation,
          isNot(Confirmation.none),
          reason: '${d.name} must require confirmation',
        );
      }
    });

    test('no descriptor advertises externalCall', () {
      // §4.5: externalCall side effects are never LLM-triggered. Such
      // a descriptor would be rejected by the dispatcher anyway, so
      // shipping one is a configuration bug, not a feature.
      for (final d in allToolDescriptors) {
        expect(
          d.sideEffect,
          isNot(SideEffect.externalCall),
          reason: '${d.name} must not be externalCall',
        );
      }
    });
  });

  group('AiTrace roundtrip', () {
    test('trace with spans + tool calls round-trips', () {
      const trace = AiTrace(
        requestId: 'trace_1',
        startedAtIso: '2026-05-10T10:30:00Z',
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.suggest,
          label: 'cashflow_explain',
        ),
        backend: Backend.hybrid,
        budgetTier: BudgetTier.standard,
        routingReason: 'capability_analyze_online',
        totalDurationMs: 3450,
        spans: <AiSpan>[
          AiSpan(
            id: 'turn',
            kind: AiSpanKind.turn,
            name: 'turn',
            startOffsetMs: 0,
            durationMs: 200,
          ),
          AiSpan(
            id: 'r1',
            parentId: 'turn',
            kind: AiSpanKind.llm,
            name: 'llm:round-1',
            startOffsetMs: 0,
            durationMs: 180,
            tokens: SpanTokens(input: 40, output: 12),
          ),
          AiSpan(
            id: 'tool:t1',
            parentId: 'r1',
            kind: AiSpanKind.tool,
            name: 'tool:get_holdings',
            startOffsetMs: 20,
            durationMs: 180,
          ),
        ],
      );
      final decoded = AiTrace.fromJson(
        jsonDecode(jsonEncode(trace.toJson())) as Map<String, Object?>,
      );
      expect(decoded.requestId, trace.requestId);
      expect(decoded.intent.label, trace.intent.label);
      expect(decoded.backend, Backend.hybrid);
      expect(decoded.spans, hasLength(3));
      expect(decoded.toolSpans.single.name, 'tool:get_holdings');
      expect(decoded.llmRoundCount, 1);
      expect(decoded.tokenTotals.input, 40);
      // Wave 30: terminalReason defaults to done when not provided.
      expect(decoded.terminalReason, TerminalReason.done);
    });

    test('trace with explicit terminalReason round-trips (Wave 30)', () {
      for (final reason in TerminalReason.values) {
        const seed = AiTrace(
          requestId: 'r',
          startedAtIso: '2026-05-12T00:00:00Z',
          intent: IntentHint(
            capability: Capability.analyze,
            risk: RiskLevel.suggest,
          ),
          backend: Backend.cloud,
          budgetTier: BudgetTier.small,
          routingReason: 'test',
          totalDurationMs: 100,
        );
        // Build with the desired reason via copy through json.
        final json = seed.toJson();
        json['terminal_reason'] = reason.wire;
        final decoded = AiTrace.fromJson(json);
        expect(decoded.terminalReason, reason, reason: 'reason=$reason');
      }
    });

    test(
      'Wave 33: AiTrace.invocation round-trips with object + context keys',
      () {
        const seed = AiTrace(
          requestId: 'r',
          startedAtIso: '2026-05-12T00:00:00Z',
          intent: IntentHint(
            capability: Capability.analyze,
            risk: RiskLevel.suggest,
          ),
          backend: Backend.cloud,
          budgetTier: BudgetTier.small,
          routingReason: 'capsule_explain',
          totalDurationMs: 200,
          invocation: <String, Object?>{
            'source': 'expense_detail',
            'intent': 'explain_change',
            'object_type': 'expense',
            'object_id': 'exp_42',
            'context_keys': <String>['timeframe'],
          },
        );
        final decoded = AiTrace.fromJson(
          jsonDecode(jsonEncode(seed.toJson())) as Map<String, Object?>,
        );
        expect(decoded.invocation, isNotNull);
        expect(decoded.invocation!['source'], 'expense_detail');
        expect(decoded.invocation!['intent'], 'explain_change');
        expect(decoded.invocation!['object_type'], 'expense');
        expect(decoded.invocation!['object_id'], 'exp_42');
        expect(decoded.invocation!['context_keys'], <String>['timeframe']);
      },
    );

    test('Wave 33: AiTrace.invocation omitted when null', () {
      const seed = AiTrace(
        requestId: 'r',
        startedAtIso: '2026-05-12T00:00:00Z',
        intent: IntentHint(
          capability: Capability.analyze,
          risk: RiskLevel.info,
        ),
        backend: Backend.cloud,
        budgetTier: BudgetTier.small,
        routingReason: 'chat_typed',
        totalDurationMs: 50,
      );
      final json = seed.toJson();
      expect(json.containsKey('invocation'), isFalse);
    });

    test('legacy AiTrace JSON without terminal_reason defaults to done', () {
      // Simulates old persisted rows from before Wave 30. The decoder
      // must tolerate the missing field rather than crash.
      final json = <String, Object?>{
        'request_id': 'old',
        'started_at': '2026-01-01T00:00:00Z',
        'intent': {'capability': 'analyze', 'risk': 'info'},
        'backend': 'cloud',
        'budget_tier': 'small',
        'routing_reason': 'legacy',
        'used_cloud': true,
        'used_raw_ledger': false,
        'total_duration_ms': 10,
        'disclosures': <Object?>[],
      };
      final decoded = AiTrace.fromJson(json);
      expect(decoded.terminalReason, TerminalReason.done);
    });
  });

  group('ContextPack version', () {
    test('current version is 1.0', () {
      expect(kCurrentContextPackVersion.major, 1);
      expect(kCurrentContextPackVersion.minor, 0);
    });
  });

  group('AnalyticalUpload wire shape (tool output)', () {
    test('round-trips a single upload with payload JSON shape', () {
      const upload = AnalyticalUpload(
        kind: 'anomaly_flag',
        id: 'expense_monthly_spike|2026-05',
        payload: <String, Object?>{
          'category': 'all_expense',
          'kind': 'monthly_spike',
          'delta_pct': 42,
          'severity': 'warn',
        },
      );
      final decoded = AnalyticalUpload.fromJson(
        jsonDecode(jsonEncode(upload.toJson())) as Map<String, Object?>,
      );
      expect(decoded.kind, 'anomaly_flag');
      expect(decoded.id, upload.id);
      expect(decoded.payload['delta_pct'], 42);
    });
  });
}

ContextPack _samplePack() => ContextPack(
  version: kCurrentContextPackVersion,
  base: _sampleBase(),
  task: const TaskContext(
    route: RouteContext(path: '/expense', area: 'expense'),
    intent: IntentHint(
      capability: Capability.analyze,
      risk: RiskLevel.suggest,
      label: 'monthly_food_explain',
    ),
    signals: <RecentSignal>[
      RecentSignal(
        kind: SignalKind.spendingSpike,
        severity: SignalSeverity.warn,
        summaryZh: '本月餐饮支出环比 +37%',
        detailRef: 'anomaly:fr_2026_04',
      ),
    ],
  ),
  budget: PrivacyBudget.standard,
);

BaseContext _sampleBase() => const BaseContext(
  preferredCurrency: 'USD',
  riskPreference: RiskPreference.moderate,
  accounts: AccountSummary(
    totalCount: 9,
    byKind: <String, int>{
      'cash': 2,
      'deposit': 1,
      'security': 4,
      'crypto': 1,
      'liability': 1,
    },
  ),
  cashflow: CashflowSummary(
    baseCurrency: 'USD',
    monthsCovered: 6,
    averageInflowMinor: '850000',
    averageOutflowMinor: '420000',
    trend: CashflowTrend.improving,
  ),
  fireGoal: FireGoalSummary(
    targetMinor: '250000000',
    currency: 'USD',
    progressFraction: 0.32,
    yearsRemainingEstimate: 12.4,
  ),
);
