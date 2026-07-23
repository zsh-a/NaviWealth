import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/production_ai_catalog.dart';
import 'package:naviwealth/core/ai/contracts/interaction.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/ask_user_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

Future<Map<String, Object?>> _invoke(Map<String, Object?> input) {
  const tool = AskUserTool();
  final c = ProviderContainer();
  addTearDown(c.dispose);
  final probe = FutureProvider<Map<String, Object?>>((ref) async {
    final out = await tool.invoke(
      DeviceToolContext(
        ref: ref,
        session: DeviceSession(messages: const <AnthropicChatMessage>[]),
      ),
      input,
    );
    return (out! as Map).cast<String, Object?>();
  });
  c.listen(probe, (_, _) {});
  return c.read(probe.future);
}

void main() {
  group('AskUserTool', () {
    const tool = AskUserTool();

    test('descriptor mirror match (shell, read, no side effect)', () {
      expect(tool.name, 'ask_user');
      expect(tool.inputSchema['required'], <String>['title', 'options']);
      final d = productionToolDescriptors['ask_user'];
      expect(d, isNotNull);
      expect(d!.access, Access.read);
      expect(d.sideEffect, SideEffect.none);
      expect(d.domain, kDomainShell);
    });

    test('normalises a valid request and marks awaiting_user', () async {
      final out = await _invoke(<String, Object?>{
        'title': '状态管理方案',
        'context': '离线优先。',
        'options': [
          {
            'id': 'riverpod',
            'label': 'Riverpod + Drift',
            'pros': ['清晰分层'],
            'recommended': true,
          },
          {'label': 'BLoC'},
        ],
      });
      expect(out['type'], 'decision_request');
      expect(out['title'], '状态管理方案');
      expect(out['awaiting_user'], isTrue);
      expect(out['allow_custom'], isTrue); // defaults true
      final options = (out['options'] as List).cast<Object?>();
      expect(options, hasLength(2));
      final first = (options.first as Map).cast<String, Object?>();
      expect(first['id'], 'riverpod');
      expect(first['recommended'], isTrue);
      // id falls back to label when omitted.
      expect((options[1] as Map)['id'], 'BLoC');
      final interaction = AiInteractionEnvelope.tryParse(out['interaction']);
      expect(interaction, isNotNull);
      expect(interaction?.kind, AiInteractionKind.choice);
      expect(interaction?.resumeKind, AiInteractionResumeKind.chatTurn);
      expect(interaction?.options.map((option) => option.id), [
        'riverpod',
        'BLoC',
      ]);
    });

    test('rejects fewer than 2 valid options', () async {
      final out = await _invoke(<String, Object?>{
        'title': 't',
        'options': [
          {'label': 'only'},
          {'no_label': true},
        ],
      });
      expect(out['code'], 'bad_request');
    });

    test('rejects missing title', () async {
      final out = await _invoke(<String, Object?>{
        'options': [
          {'label': 'a'},
          {'label': 'b'},
        ],
      });
      expect(out['code'], 'bad_request');
    });

    test('honours allow_custom:false', () async {
      final out = await _invoke(<String, Object?>{
        'title': 't',
        'allow_custom': false,
        'options': [
          {'label': 'a'},
          {'label': 'b'},
        ],
      });
      expect(out['allow_custom'], isFalse);
    });
  });
}
