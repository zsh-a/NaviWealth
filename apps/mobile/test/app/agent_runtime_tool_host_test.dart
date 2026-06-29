import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/composition/device_tools_provider.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

void main() {
  test('tool.call dispatches to the device dispatcher', () async {
    final dispatcher = _FakeDispatcher();
    final host = AgentRuntimeToolHost(dispatcher: dispatcher);

    final response = await host.handleLine(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'tool_call',
        'method': 'tool.call',
        'params': <String, Object?>{
          'name': 'read_fake',
          'input': <String, Object?>{'id': 'abc'},
        },
      }),
    );

    final json = jsonDecode(response) as Map<String, Object?>;
    expect(json['jsonrpc'], '2.0');
    expect(json['id'], 'tool_call');
    expect(json['error'], isNull);
    expect(json['result'], <String, Object?>{
      'tool': 'read_fake',
      'input': <String, Object?>{'id': 'abc'},
    });
    expect(dispatcher.calls.single.name, 'read_fake');
  });

  test('tool result error envelopes are returned as result payloads', () async {
    final host = AgentRuntimeToolHost(
      dispatcher: _FakeDispatcher(
        output: const <String, Object?>{
          'error': 'denied',
          'code': 'policy_denied',
        },
      ),
    );

    final response = await host.handleLine(
      jsonEncode(<String, Object?>{
        'id': 1,
        'method': 'tool.call',
        'params': <String, Object?>{'name': 'blocked'},
      }),
    );

    final json = jsonDecode(response) as Map<String, Object?>;
    expect(json['error'], isNull);
    expect(json['result'], <String, Object?>{
      'error': 'denied',
      'code': 'policy_denied',
    });
  });

  test('invalid requests return JSON-RPC errors', () async {
    final host = AgentRuntimeToolHost(dispatcher: _FakeDispatcher());

    expect(
      (jsonDecode(await host.handleLine('{')) as Map<String, Object?>)['error'],
      containsPair('code', -32700),
    );
    expect(
      (jsonDecode(
            await host.handleLine(
              jsonEncode(<String, Object?>{'method': 'unknown'}),
            ),
          )
          as Map<String, Object?>)['error'],
      containsPair('code', -32601),
    );
    expect(
      (jsonDecode(
            await host.handleLine(
              jsonEncode(<String, Object?>{
                'id': 'bad',
                'method': 'tool.call',
                'params': <String, Object?>{},
              }),
            ),
          )
          as Map<String, Object?>)['error'],
      containsPair('code', -32602),
    );
  });

  test('dispatcher throws become internal JSON-RPC errors', () async {
    final host = AgentRuntimeToolHost(
      dispatcher: _FakeDispatcher(throwOnDispatch: true),
    );

    final response = await host.handleLine(
      jsonEncode(<String, Object?>{
        'id': 'explode',
        'method': 'tool.call',
        'params': <String, Object?>{'name': 'boom'},
      }),
    );

    final json = jsonDecode(response) as Map<String, Object?>;
    expect(json['id'], 'explode');
    expect(json['error'], containsPair('code', -32000));
  });

  test('provider builds a host from active DeviceTools', () async {
    final container = ProviderContainer(
      overrides: [
        deviceToolsProvider.overrideWith(
          (ref) => const <DeviceTool>[_EchoDeviceTool()],
        ),
      ],
    );
    addTearDown(container.dispose);

    final host = container.read(agentRuntimeToolHostProvider);
    final response = await host.handleLine(
      jsonEncode(<String, Object?>{
        'id': 'active-tool',
        'method': 'tool.call',
        'params': <String, Object?>{
          'name': 'echo_active',
          'input': <String, Object?>{'value': 11},
        },
      }),
    );

    final json = jsonDecode(response) as Map<String, Object?>;
    expect(json['id'], 'active-tool');
    expect(json['result'], <String, Object?>{
      'active_tool': true,
      'input': <String, Object?>{'value': 11},
    });
  });

  test(
    'runAgentRuntimeToolHostLines processes JSONL streams in order',
    () async {
      final host = AgentRuntimeToolHost(dispatcher: _FakeDispatcher());
      final outputs = <String>[];

      await runAgentRuntimeToolHostLines(
        host: host,
        input: Stream<String>.fromIterable(<String>[
          jsonEncode(<String, Object?>{
            'id': 1,
            'method': 'tool.call',
            'params': <String, Object?>{'name': 'first'},
          }),
          jsonEncode(<String, Object?>{
            'id': 2,
            'method': 'tool.call',
            'params': <String, Object?>{'name': 'second'},
          }),
        ]),
        output: outputs.add,
      );

      expect(outputs, hasLength(2));
      expect((jsonDecode(outputs[0]) as Map<String, Object?>)['id'], 1);
      expect((jsonDecode(outputs[1]) as Map<String, Object?>)['id'], 2);
    },
  );
}

class _FakeDispatcher implements DeviceToolDispatcher {
  _FakeDispatcher({this.output, this.throwOnDispatch = false});

  final Object? output;
  final bool throwOnDispatch;
  final List<_Call> calls = <_Call>[];

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    if (throwOnDispatch) throw StateError('boom');
    calls.add(_Call(name, input));
    return output ?? <String, Object?>{'tool': name, 'input': input};
  }
}

class _Call {
  const _Call(this.name, this.input);

  final String name;
  final Object? input;
}

class _EchoDeviceTool implements DeviceTool {
  const _EchoDeviceTool();

  @override
  String get name => 'echo_active';

  @override
  String get description => 'Echo active test tool';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    return <String, Object?>{'active_tool': true, 'input': input};
  }
}
