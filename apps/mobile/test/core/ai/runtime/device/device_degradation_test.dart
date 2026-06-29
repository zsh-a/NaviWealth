import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/production_ai_catalog.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/ai_runtime.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart';
import 'package:naviwealth/features/ai_chat/data/runtime_routing_api_client.dart';
import 'package:naviwealth/features/ai_chat/ui/ai_transparency_badge.dart';

AiTrace _trace({
  required Backend backend,
  String routingReason = 'capability_classify',
}) => AiTrace(
  requestId: 'r',
  startedAtIso: '2026-05-16T00:00:00Z',
  intent: const IntentHint(
    capability: Capability.analyze,
    risk: RiskLevel.info,
  ),
  backend: backend,
  budgetTier: BudgetTier.small,
  routingReason: routingReason,
  totalDurationMs: 1200,
);

AuthSession _session() => AuthSession(
  accessToken: 't',
  expiresAt: DateTime.utc(2030),
  userId: 'u',
  deviceId: 'd',
);

class _ScriptedDevice implements DeviceChatRunner {
  _ScriptedDevice(this._events, {this.throwAfter});
  final List<AiChatEvent> _events;
  final int? throwAfter; // throw after N yielded events (null = never)

  @override
  Stream<AiChatEvent> run({
    required List<WireMessage> messages,
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    var n = 0;
    for (final e in _events) {
      if (throwAfter != null && n == throwAfter) {
        throw StateError('device socket closed');
      }
      yield e;
      n++;
    }
    if (throwAfter != null && n == throwAfter) {
      throw StateError('device socket closed');
    }
  }
}

Future<List<AiChatEvent>> _run(RuntimeRoutingAiChatApiClient c) => c
    .chat(
      session: _session(),
      messages: const [WireMessage(role: 'user', content: 'hi')],
    )
    .toList();

void main() {
  group('formatAiTraceBadge — device-direct text (W-D6)', () {
    test('device + device_llm_direct → "未经我方服务器"', () {
      expect(
        isDirectProviderRoutingReason(kDeviceLlmDirectRoutingReason),
        true,
      );
      final s = formatAiTraceBadge(
        _trace(
          backend: Backend.device,
          routingReason: kDeviceLlmDirectRoutingReason,
        ),
      );
      expect(s, contains('端侧直连模型'));
      expect(s, contains('未经我方服务器'));
    });

    test('device + frb_agent_runtime_profile → "未经我方服务器"', () {
      expect(
        isDirectProviderRoutingReason(kFrbAgentRuntimeProfileRoutingReason),
        true,
      );
      final s = formatAiTraceBadge(
        _trace(
          backend: Backend.device,
          routingReason: kFrbAgentRuntimeProfileRoutingReason,
        ),
      );
      expect(s, contains('端侧直连模型'));
      expect(s, contains('未经我方服务器'));
    });

    test('device + frb_chat → "未经我方服务器"', () {
      expect(isDirectProviderRoutingReason(kFrbChatRoutingReason), true);
      final s = formatAiTraceBadge(
        _trace(backend: Backend.device, routingReason: kFrbChatRoutingReason),
      );
      expect(s, contains('端侧直连模型'));
      expect(s, contains('未经我方服务器'));
    });

    test('device without that reason stays "全部本地处理"', () {
      expect(isDirectProviderRoutingReason('capability_classify'), false);
      final s = formatAiTraceBadge(_trace(backend: Backend.device));
      expect(s, contains('全部本地处理'));
      expect(s, isNot(contains('未经我方服务器')));
    });

    test('device_unavailable is not disclosed as provider direct routing', () {
      expect(
        isDirectProviderRoutingReason(kDeviceUnavailableRoutingReason),
        false,
      );
      final s = formatAiTraceBadge(
        _trace(
          backend: Backend.device,
          routingReason: kDeviceUnavailableRoutingReason,
        ),
      );
      expect(s, contains('全部本地处理'));
      expect(s, isNot(contains('未经我方服务器')));
    });

    test('legacy cloud trace is shown as device model inference', () {
      expect(
        formatAiTraceBadge(_trace(backend: Backend.cloud)),
        contains('端侧模型推理'),
      );
    });
  });

  group(
    'RuntimeRoutingAiChatApiClient — W-D7 device-only (no cloud relay)',
    () {
      test(
        'no device → unavailable error + done, never a cloud relay',
        () async {
          const c = RuntimeRoutingAiChatApiClient();
          expect(c.usesDevice, isFalse);
          final out = await _run(c);
          expect(out, hasLength(2));
          expect((out.first as ErrorEvent).code, 'device_unavailable');
          expect((out.last as DoneEvent).stopReason, 'error');
        },
      );

      test(
        'feature default stays unavailable until bootstrap injects FRB chat',
        () async {
          final container = ProviderContainer();
          addTearDown(container.dispose);

          final api = container.read(aiChatApiClientProvider);
          final out = await api
              .chat(
                session: _session(),
                messages: const [WireMessage(role: 'user', content: 'hi')],
              )
              .toList();

          expect((out.first as ErrorEvent).code, 'device_unavailable');
          expect((out.last as DoneEvent).rounds, 0);
        },
      );

      test('device produces content → passed through unchanged', () async {
        final c = RuntimeRoutingAiChatApiClient(
          device: _ScriptedDevice(const [
            TextEvent('device-answer'),
            DoneEvent(stopReason: 'end_turn', rounds: 1),
          ]),
        );
        expect(c.usesDevice, isTrue);
        final out = await _run(c);
        expect((out.first as TextEvent).text, 'device-answer');
        expect(out.last, isA<DoneEvent>());
      });

      test(
        'device error passes through verbatim (no cloud suppression)',
        () async {
          final c = RuntimeRoutingAiChatApiClient(
            device: _ScriptedDevice(const [
              ErrorEvent('bad api key', code: 'provider_error'),
              DoneEvent(stopReason: 'error', rounds: 1),
            ]),
          );
          final out = await _run(c);
          expect((out.first as ErrorEvent).code, 'provider_error');
          expect(out.last, isA<DoneEvent>());
        },
      );

      test('device throws → propagates (no failover)', () async {
        final c = RuntimeRoutingAiChatApiClient(
          device: _ScriptedDevice(const [TextEvent('partial')], throwAfter: 1),
        );
        expect(_run(c), throwsA(isA<StateError>()));
      });
    },
  );

  group('device tool static contract (W-D6)', () {
    test('every production device tool resolves in the descriptor mirror', () {
      for (final tool in productionDeviceTools) {
        final d = productionToolDescriptors[tool.name];
        expect(
          d,
          isNotNull,
          reason:
              '${tool.name} is dispatchable on device but missing from '
              'tool_descriptor.dart — wire/descriptor drift (§10)',
        );
        // §4.5 invariant: a device tool may be a deviceLocalWrite
        // proposal (propose_*, gated by the confirm flow) but must
        // NEVER be an externalCall — those are never LLM-triggered.
        expect(
          d!.sideEffect,
          isNot(SideEffect.externalCall),
          reason: tool.name,
        );
      }
    });

    test('every descriptor is advertised by the device registry', () {
      final advertised = productionDeviceToolRegistry.names.toSet();
      for (final descriptor in productionToolDescriptors.values) {
        expect(
          advertised,
          contains(descriptor.name),
          reason:
              '${descriptor.name} has ToolDescriptor metadata but is not '
              'registered in the production device tool registry',
        );
      }
    });

    test('registry advertises exactly the canonical set, sorted', () {
      final names = productionDeviceToolRegistry.schemas().map((s) => s.name);
      expect(names, [
        'ask_user',
        'build_context',
        'find_similar_knowledge',
        'get_activity_summary',
        'get_anomaly_flags',
        'get_asset_allocation',
        'get_body_battery_trend',
        'get_cashflow_buckets',
        'get_fire_buckets',
        'get_fire_plan',
        'get_fire_review',
        'get_fire_state',
        'get_fire_stress_tests',
        'get_geo_breakdown',
        'get_holdings',
        'get_hrv_trend',
        'get_industry_breakdown',
        'get_investment_performance',
        'get_market_cap_breakdown',
        'get_net_worth_summary',
        'get_options_income_opportunities',
        'get_options_strategy_profile',
        'get_recent_sleep_summary',
        'get_recovery_signal',
        'get_recurring_patterns',
        'get_refund_links',
        'get_stress_trend',
        'get_subscription_changes',
        'get_transfer_links',
        'get_wheel_lifecycle',
        'list_active_principles',
        'list_blocked_actions',
        'list_due_reviews',
        'list_due_routines',
        'list_inbox_triage_candidates',
        'list_open_actions',
        'list_open_assumptions',
        'list_payment_accounts',
        'list_triage_decisions',
        'propose_account_create',
        'propose_action',
        'propose_action_status_update',
        'propose_asset_valuation',
        'propose_capture',
        'propose_commitment',
        'propose_concept_link',
        'propose_expense',
        'propose_fire_bucket_rule',
        'propose_fire_plan_update',
        'propose_liability_payment',
        'propose_merge',
        'propose_options_journal_entry',
        'propose_options_profile_update',
        'propose_progress',
        'propose_project',
        'propose_routine',
        'propose_trade',
        'query_memory',
        'queue_inbox_classification',
        'queue_inbox_tags',
        'queue_link_to_decision',
        'read_account_window',
        'read_asset_window',
        'read_category_window',
        'recall_decision',
        'record_body_measurement',
        'review_knowledge_health',
        'search_knowledge',
        'search_notes',
        'simulate_fire_plan',
        'summarize_execution_progress',
        'summarize_topic_evolution',
      ]);
    });
  });
}
