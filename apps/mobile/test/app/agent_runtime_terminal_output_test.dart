import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/agent_runtime_terminal_output.dart';

void main() {
  test('indexes terminal tool_results by tool name', () {
    final results = agentRuntimeTerminalToolResultsByName(
      const <String, Object?>{
        'output': <String, Object?>{
          'tool_results': <Object?>[
            <String, Object?>{
              'tool_call': <String, Object?>{'name': 'list_open_actions'},
              'tool_response': <String, Object?>{
                'result': <String, Object?>{
                  'actions': <Object?>['a1'],
                },
              },
            },
            <String, Object?>{
              'tool_call': <String, Object?>{'name': 'summarize_progress'},
              'tool_response': <String, Object?>{
                'result': <String, Object?>{'active_project_count': 2},
              },
            },
          ],
        },
      },
    );

    expect(results['list_open_actions']?['actions'], <Object?>['a1']);
    expect(results['summarize_progress']?['active_project_count'], 2);
  });

  test('indexes single terminal tool_result by tool name', () {
    final result = agentRuntimeTerminalToolResult(const <String, Object?>{
      'output': <String, Object?>{
        'tool_call': <String, Object?>{'name': 'get_hrv_trend'},
        'tool_result': <String, Object?>{'points': <Object?>[]},
      },
    }, 'get_hrv_trend');

    expect(result, <String, Object?>{'points': <Object?>[]});
  });

  test('reads unambiguous single terminal tool_result without tool_call', () {
    final result = agentRuntimeTerminalToolResult(const <String, Object?>{
      'output': <String, Object?>{
        'tool_result': <String, Object?>{'assumptions': <Object?>[]},
      },
    }, 'list_open_assumptions');

    expect(result, <String, Object?>{'assumptions': <Object?>[]});
  });

  test('keeps multi-tool result when single fallback has same name', () {
    final results = agentRuntimeTerminalToolResultsByName(
      const <String, Object?>{
        'output': <String, Object?>{
          'tool_results': <Object?>[
            <String, Object?>{
              'tool_call': <String, Object?>{'name': 'same_tool'},
              'tool_response': <String, Object?>{
                'result': <String, Object?>{'source': 'loop'},
              },
            },
          ],
          'tool_call': <String, Object?>{'name': 'same_tool'},
          'tool_result': <String, Object?>{'source': 'single'},
        },
      },
    );

    expect(results['same_tool'], <String, Object?>{'source': 'loop'});
  });

  test('returns empty results for malformed terminal output', () {
    expect(
      agentRuntimeTerminalToolResultsByName(const <String, Object?>{
        'output': 'bad',
      }),
      isEmpty,
    );
    expect(
      agentRuntimeTerminalToolResult(const <String, Object?>{
        'output': null,
      }, 'missing'),
      isNull,
    );
  });
}
