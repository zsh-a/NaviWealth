import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_terminal_output.dart';

void main() {
  test('indexes terminal effect_results by tool name', () {
    final results = agentRuntimeTerminalEffectResultsByToolName(
      const <String, Object?>{
        'output': <String, Object?>{
          'effect_results': <Object?>[
            <String, Object?>{
              'effect': <String, Object?>{
                'kind': 'tool',
                'name': 'list_open_actions',
              },
              'effect_response': <String, Object?>{
                'result': <String, Object?>{
                  'actions': <Object?>['a1'],
                },
              },
            },
            <String, Object?>{
              'effect': <String, Object?>{
                'kind': 'tool',
                'name': 'summarize_progress',
              },
              'effect_response': <String, Object?>{
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

  test('indexes single terminal effect_result by tool name', () {
    final result = agentRuntimeTerminalEffectResultForTool(
      const <String, Object?>{
        'output': <String, Object?>{
          'effect': <String, Object?>{'kind': 'tool', 'name': 'get_hrv_trend'},
          'effect_result': <String, Object?>{'points': <Object?>[]},
        },
      },
      'get_hrv_trend',
    );

    expect(result, <String, Object?>{'points': <Object?>[]});
  });

  test('does not infer tool name for single effect_result without effect', () {
    final result = agentRuntimeTerminalEffectResultForTool(
      const <String, Object?>{
        'output': <String, Object?>{
          'effect_result': <String, Object?>{'assumptions': <Object?>[]},
        },
      },
      'list_open_assumptions',
    );

    expect(result, isNull);
  });

  test('keeps multi-effect result when single fallback has same name', () {
    final results = agentRuntimeTerminalEffectResultsByToolName(
      const <String, Object?>{
        'output': <String, Object?>{
          'effect_results': <Object?>[
            <String, Object?>{
              'effect': <String, Object?>{'kind': 'tool', 'name': 'same_tool'},
              'effect_response': <String, Object?>{
                'result': <String, Object?>{'source': 'loop'},
              },
            },
          ],
          'effect': <String, Object?>{'kind': 'tool', 'name': 'same_tool'},
          'effect_result': <String, Object?>{'source': 'single'},
        },
      },
    );

    expect(results['same_tool'], <String, Object?>{'source': 'loop'});
  });

  test('returns empty results for malformed terminal output', () {
    expect(
      agentRuntimeTerminalEffectResultsByToolName(const <String, Object?>{
        'output': 'bad',
      }),
      isEmpty,
    );
    expect(
      agentRuntimeTerminalEffectResultForTool(const <String, Object?>{
        'output': null,
      }, 'missing'),
      isNull,
    );
  });
}
