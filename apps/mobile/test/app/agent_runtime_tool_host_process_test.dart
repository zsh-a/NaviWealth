import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bin/agent_runtime_tool_host.dart speaks JSONL tool.call', () async {
    final process = await Process.start('dart', <String>[
      'run',
      'bin/agent_runtime_tool_host.dart',
      '--unavailable',
    ]);
    addTearDown(() {
      process.kill();
    });

    process.stdin.writeln(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 'tool_call',
        'method': 'tool.call',
        'params': <String, Object?>{
          'name': 'anything',
          'input': <String, Object?>{'value': 1},
        },
      }),
    );
    await process.stdin.flush();
    await process.stdin.close();

    final output = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((line) => line.trimLeft().startsWith('{'));
    final json = jsonDecode(output) as Map<String, Object?>;
    expect(json['jsonrpc'], '2.0');
    expect(json['id'], 'tool_call');
    expect(json['error'], isNull);
    expect(json['result'], containsPair('code', 'tool_unavailable'));

    expect(await process.exitCode, 0);
  });

  test(
    'bin/agent_runtime_tool_host.dart shell mode handles ask_user',
    () async {
      final process = await Process.start('dart', <String>[
        'run',
        'bin/agent_runtime_tool_host.dart',
        '--shell',
      ]);
      addTearDown(() {
        process.kill();
      });

      process.stdin.writeln(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'decision',
          'method': 'tool.call',
          'params': <String, Object?>{
            'name': 'ask_user',
            'input': <String, Object?>{
              'title': 'Pick a runtime path',
              'options': <Object?>[
                <String, Object?>{'label': 'Embedded'},
                <String, Object?>{'label': 'Process'},
              ],
            },
          },
        }),
      );
      await process.stdin.flush();
      await process.stdin.close();

      final output = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line.trimLeft().startsWith('{'));
      final json = jsonDecode(output) as Map<String, Object?>;
      final result = json['result'] as Map<String, Object?>;
      expect(json['jsonrpc'], '2.0');
      expect(json['id'], 'decision');
      expect(json['error'], isNull);
      expect(result['type'], 'decision_request');
      expect(result['awaiting_user'], true);
      expect(result['domain'], 'shell');

      expect(await process.exitCode, 0);
    },
  );

  test(
    'bin/agent_runtime_tool_host.dart rejects app-backed domain flags',
    () async {
      final process = await Process.start('dart', <String>[
        'run',
        'bin/agent_runtime_tool_host.dart',
        '--domains=all',
      ]);
      addTearDown(() {
        process.kill();
      });

      final stderrLine = await process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line.contains('protocol smoke-test only'));

      expect(stderrLine, contains('agent_runtime_tool_host_headless.dart'));
      expect(await process.exitCode, 64);
    },
  );
}
