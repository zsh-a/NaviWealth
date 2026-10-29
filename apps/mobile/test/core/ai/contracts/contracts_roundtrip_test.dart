import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/production_ai_catalog.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';

void main() {
  group('ToolDescriptor roundtrip', () {
    test('descriptor round-trips with all axes', () {
      const desc = ToolDescriptor(
        domain: AiDomain.shell(),
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
      // The union is derived from production DomainPack registrations.
      // Keep the exact count pinned so adding or removing a device tool is
      // an intentional contract change.
      expect(productionToolDescriptors.values, hasLength(68));
      for (final name in ['search_bcr_notes', 'read_bcr_note']) {
        final descriptor = productionToolDescriptors[name]!;
        expect(descriptor.access, Access.read);
        expect(descriptor.sideEffect, SideEffect.none);
      }
      expect(
        productionToolDescriptors['propose_scheduled_task']
            ?.requiresConfirmation,
        Confirmation.oneTap,
      );
      expect(
        productionToolDescriptors['propose_options_profile_update']?.sideEffect,
        SideEffect.deviceLocalWrite,
      );
      expect(
        productionToolDescriptors['list_payment_accounts']?.allowedContextTier,
        BudgetTier.standard,
      );
      expect(
        productionToolDescriptors['propose_expense']?.sideEffect,
        SideEffect.deviceLocalWrite,
      );
      expect(
        productionToolDescriptors['propose_income']?.sideEffect,
        SideEffect.deviceLocalWrite,
      );
      expect(productionToolDescriptors['get_journal_entries'], isNull);
    });

    // Regression — 2026-05-24 boundary audit removed `allowed_runtimes`,
    // `read_model_layer`, and `used_cloud` from ToolDescriptor's wire
    // shape. Silent re-introduction would mean drift back toward the
    // multi-runtime / freshness-gated design we deliberately deleted.
    // D-1.3 added `domain` so the catalog can partition shell vs
    // finance tools — bumping the canonical key count from 6 → 7.
    test('toJson emits exactly the seven documented keys', () {
      const desc = ToolDescriptor(
        domain: AiDomain.shell(),
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
        'domain': 'shell',
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
      final proposals = productionToolDescriptors.values.where(
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
      for (final d in productionToolDescriptors.values) {
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
          domain: AiDomain.shell(),
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
            domain: AiDomain.shell(),
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
            domain: AiDomain.shell(),
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
          domain: AiDomain.shell(),
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
        'intent': {'capability': 'analyze', 'risk': 'info', 'domain': 'shell'},
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
