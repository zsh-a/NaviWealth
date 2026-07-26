import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/options_income/ai_tools/propose_leaps_call_position_tool.dart';

Future<Map<String, Object?>> _invoke(Map<String, Object?> input) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final probe = FutureProvider<Map<String, Object?>>((ref) async {
    final output = await const ProposeLeapsCallPositionTool().invoke(
      DeviceToolContext(
        ref: ref,
        session: DeviceSession(messages: const <AnthropicChatMessage>[]),
      ),
      input,
    );
    return (output! as Map).cast<String, Object?>();
  });
  container.listen(probe, (_, _) {});
  return container.read(probe.future);
}

void main() {
  test('stages a separate LEAPS proposal with normalized defaults', () async {
    final output = await _invoke({
      'underlying': 'aapl',
      'option_symbol': 'AAPL280121C00180000',
      'opened_at_iso': '2026-07-20T00:00:00Z',
      'expiration_at_iso': '2028-01-21T00:00:00Z',
      'strike_price': 180,
      'entry_debit': 1200,
      'current_delta': 0.7,
    });

    expect(output['status'], 'ready');
    expect(output['kind'], 'leaps_call_position');
    final payload = (output['payload']! as Map).cast<String, Object?>();
    expect(payload['underlying'], 'AAPL');
    expect(payload['contract_size'], 100);
    expect(payload['status'], 'open');
  });

  test('rejects expiration on or before open date', () async {
    final output = await _invoke({
      'underlying': 'AAPL',
      'option_symbol': 'AAPL',
      'opened_at_iso': '2026-07-20T00:00:00Z',
      'expiration_at_iso': '2026-07-20T00:00:00Z',
      'strike_price': 180,
      'entry_debit': 1200,
    });
    expect(output['code'], 'bad_request');
  });

  test('rejects a non-numeric optional market snapshot', () async {
    final output = await _invoke({
      'underlying': 'AAPL',
      'option_symbol': 'AAPL280121C00180000',
      'opened_at_iso': '2026-07-20T00:00:00Z',
      'expiration_at_iso': '2028-01-21T00:00:00Z',
      'strike_price': 180,
      'entry_debit': 1200,
      'current_mark': 'unknown',
    });

    expect(output['code'], 'bad_request');
  });
}
