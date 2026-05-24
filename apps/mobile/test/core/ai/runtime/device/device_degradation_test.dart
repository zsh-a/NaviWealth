import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/runtime/ai_runtime.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool_registry.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';
import 'package:naviwealth/features/ai_chat/data/runtime_routing_api_client.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_events.dart';
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
  usedCloud: backend != Backend.device,
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
      final s = formatAiTraceBadge(
        _trace(
          backend: Backend.device,
          routingReason: kDeviceLlmDirectRoutingReason,
        ),
      );
      expect(s, contains('端侧直连模型'));
      expect(s, contains('未经我方服务器'));
    });

    test('device without that reason stays "全部本地处理"', () {
      final s = formatAiTraceBadge(_trace(backend: Backend.device));
      expect(s, contains('全部本地处理'));
      expect(s, isNot(contains('未经我方服务器')));
    });

    test('cloud unchanged', () {
      expect(
        formatAiTraceBadge(_trace(backend: Backend.cloud)),
        contains('仅云端推理'),
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
    test('every kDeviceTools name resolves in the descriptor mirror', () {
      for (final tool in kDeviceTools) {
        final d = lookupToolDescriptor(tool.name);
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
      final advertised = defaultDeviceToolRegistry().names.toSet();
      for (final descriptor in allToolDescriptors) {
        expect(
          advertised,
          contains(descriptor.name),
          reason:
              '${descriptor.name} has ToolDescriptor metadata but is not '
              'registered in kDeviceTools',
        );
      }
    });

    test('registry advertises exactly the canonical set, sorted', () {
      final names = defaultDeviceToolRegistry().schemas().map((s) => s.name);
      expect(names, [
        'get_anomaly_flags',
        'get_asset_allocation',
        'get_cashflow_buckets',
        'get_fire_buckets',
        'get_fire_plan',
        'get_fire_review',
        'get_fire_state',
        'get_fire_stress_tests',
        'get_geo_breakdown',
        'get_holdings',
        'get_industry_breakdown',
        'get_investment_performance',
        'get_market_cap_breakdown',
        'get_net_worth_summary',
        'get_options_income_opportunities',
        'get_options_strategy_profile',
        'get_recurring_patterns',
        'get_refund_links',
        'get_subscription_changes',
        'get_transfer_links',
        'list_payment_accounts',
        'propose_account_create',
        'propose_asset_valuation',
        'propose_expense',
        'propose_fire_bucket_rule',
        'propose_fire_plan_update',
        'propose_liability_payment',
        'propose_options_journal_entry',
        'propose_options_profile_update',
        'propose_trade',
        'read_account_window',
        'read_asset_window',
        'read_category_window',
        'simulate_fire_plan',
      ]);
    });
  });
}
