import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI trigger surfaces go through AiIntentInvocation entry helper', () {
    final dartFiles =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final directChatPagePushes = <String>[];
    final forbiddenOpenAiEntrypoints = <String>[];
    final showAiSheetCallSites = <String>[];
    final directAiChatPageConstructions = <String>[];

    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = _stripLineComment(lines[i]);
        if (code.trim().isEmpty) continue;
        final location = '${file.path}:${i + 1}';

        if (_pushesChatPage.hasMatch(code)) {
          directChatPagePushes.add('$location: ${code.trim()}');
        }
        if (_openAiChatEntrypoint.hasMatch(code)) {
          forbiddenOpenAiEntrypoints.add('$location: ${code.trim()}');
        }
        if (_showAiSheetCall.hasMatch(code) &&
            !_isShowAiSheetDefinition(code)) {
          showAiSheetCallSites.add(location);
        }
        if (_aiChatPageConstruction.hasMatch(code) &&
            !_isAiChatPageConstructorDeclaration(code)) {
          directAiChatPageConstructions.add(location);
        }
      }
    }

    expect(
      directChatPagePushes,
      isEmpty,
      reason:
          'AI trigger surfaces must not route-push chat pages directly; '
          'build AiIntentInvocation through askAi() so trace source, intent, '
          'object, and domain are preserved.',
    );
    expect(
      forbiddenOpenAiEntrypoints,
      isEmpty,
      reason:
          'Feature/UI layers must not introduce openAiChat(...) style entry '
          'points. Provider-specific OpenAI payload builders are allowed, but '
          'trigger surfaces must go through AiIntentInvocation.',
    );
    expect(
      showAiSheetCallSites.toSet(),
      <String>{
        'lib/features/ai_chat/ui/ask_ai.dart:51',
        'lib/features/ai_chat/ui/ask_ai.dart:55',
      },
      reason:
          'showAiSheet is the renderer, not the public trigger seam. External '
          'surfaces should call askAi(), which constructs AiIntentInvocation.',
    );
    expect(
      directAiChatPageConstructions.toSet(),
      <String>{'lib/app/router_builder.dart:195'},
      reason:
          'AiChatPage is allowed only as the read-only /settings/ai-history '
          'route. Trigger surfaces should use the bottom-sheet invocation path.',
    );
  });

  test('AI surface copy avoids generic Ask AI labels', () {
    final violations = <String>[];

    for (final file in _copyContractFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = file.path.endsWith('.arb')
            ? lines[i]
            : _stripLineComment(lines[i]);
        if (code.trim().isEmpty) continue;
        if (_genericAiLabel.hasMatch(code)) {
          violations.add('${file.path}:${i + 1}: ${code.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'AI trigger copy should name the object/action or open the '
          'assistant shell; avoid generic "Ask AI" / "AI analysis" labels.',
    );
  });

  test('AI entry topology keeps global contextual ambient ingest layers', () {
    final globalPalette = File(
      'lib/core/command_palette/default_commands.dart',
    ).readAsStringSync();
    expect(globalPalette, contains("id: 'action.askAi'"));
    expect(globalPalette, contains('onAskAi'));
    expect(globalPalette, contains('commandPaletteOpenAi'));

    final contextualCapsule = File(
      'lib/features/ai_chat/ui/ai_object_capsule.dart',
    ).readAsStringSync();
    expect(contextualCapsule, contains('class AiObjectCapsule'));
    expect(contextualCapsule, contains('askAi('));
    expect(contextualCapsule, contains('intent: intent'));
    expect(contextualCapsule, contains('AiContextChipScope.contextMapOf'));

    final ambientFeed = File(
      'lib/features/home/ui/ai_insight_feed.dart',
    ).readAsStringSync();
    expect(ambientFeed, contains('class AiInsightFeed'));
    expect(ambientFeed, contains('AiObjectCapsule('));
    expect(ambientFeed, contains("intent: 'explain_insight'"));
    expect(ambientFeed, contains("source: 'home_insight_card'"));

    final ingestProjection = File(
      'lib/features/finance/ingest/data/ingest_queue_insight_provider.dart',
    ).readAsStringSync();
    expect(ingestProjection, contains('ingestQueueInsightProvider'));
    expect(ingestProjection, contains('pendingIngestDraftsProvider'));
    expect(ingestProjection, contains('IngestQueueSummary'));
  });
}

final _pushesChatPage = RegExp(
  r'\b(?:Navigator\.push|context\.push|context\.go)\s*\([^;]*(?:AiChatPage|ChatPage)',
);
final _openAiChatEntrypoint = RegExp(r'\bopenAiChat\s*\(');
final _showAiSheetCall = RegExp(r'\bshowAiSheet\s*\(');
final _aiChatPageConstruction = RegExp(r'\bAiChatPage\s*\(');
final _genericAiLabel = RegExp(r'Ask AI|AI\s*分析|AI分析|问\s*AI|问问\s*AI');

List<File> _copyContractFiles() {
  final files = <File>[
    File('lib/l10n/app_en.arb'),
    File('lib/l10n/app_zh.arb'),
  ];

  files.addAll(
    Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.contains('/l10n/gen/'))
        .where((file) => !file.path.endsWith('.g.dart'))
        .where((file) => !file.path.endsWith('.freezed.dart')),
  );

  return files..sort((a, b) => a.path.compareTo(b.path));
}

bool _isShowAiSheetDefinition(String code) =>
    code.contains('Future<void> showAiSheet(');

bool _isAiChatPageConstructorDeclaration(String code) =>
    code.contains('const AiChatPage({');

String _stripLineComment(String line) {
  final index = line.indexOf('//');
  return index == -1 ? line : line.substring(0, index);
}
