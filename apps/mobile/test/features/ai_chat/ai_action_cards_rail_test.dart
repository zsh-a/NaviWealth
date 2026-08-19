import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/agents/agent_intents.dart';
import 'package:naviwealth/core/ai/composition/ask_ai.dart';
import 'package:naviwealth/core/ai/composition/chat_rail_content.dart';
import 'package:naviwealth/core/ai/composition/chat_rail_provider.dart';
import 'package:naviwealth/core/ai/intent/intent.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/ui/ai_action_cards_rail.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('intent-only rail card invokes askAi with object metadata', (
    tester,
  ) async {
    AiIntentInvocation? capturedInvocation;
    String? capturedObjectLabel;
    String? capturedPrefill;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRailContentSelectorProvider.overrideWith(
            (ref) =>
                (_) => const <ChatRailContent>[
                  ChatRailContent(
                    id: 'finance:agent_artifact:artifact-1',
                    headline: 'Weekly Wealth Review',
                    detail: 'Net worth moved 2.4% with cashflow pressure.',
                    icon: FLucideIcons.clipboardCheck,
                    tone: ChatRailTone.warning,
                    intent: kAgentExplainResultIntent,
                    object: AiObjectRef(
                      type: kAgentArtifactObjectType,
                      id: 'artifact-1',
                    ),
                    objectLabel: 'Weekly Wealth Review',
                    attrs: <String, Object?>{
                      'artifact_id': 'artifact-1',
                      'artifact_title': 'Weekly Wealth Review',
                      'artifact_summary':
                          'Net worth moved 2.4% with cashflow pressure.',
                    },
                    source: 'finance_agent_artifact_rail',
                  ),
                ],
          ),
          askAiSurfaceProvider.overrideWithValue((
            context, {
            invocation,
            objectLabel,
            prefill,
          }) async {
            capturedInvocation = invocation;
            capturedObjectLabel = objectLabel;
            capturedPrefill = prefill;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: const Scaffold(body: AiActionCardsRail()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Weekly Wealth Review'));
    await tester.pump();

    final invocation = capturedInvocation;
    expect(invocation, isNotNull);
    expect(invocation!.intent, kAgentExplainResultIntent);
    expect(invocation.source, 'finance_agent_artifact_rail');
    expect(invocation.domain, 'finance');
    expect(
      invocation.object,
      const AiObjectRef(type: kAgentArtifactObjectType, id: 'artifact-1'),
    );
    expect(invocation.context['artifact_id'], 'artifact-1');
    expect(invocation.context['artifact_title'], 'Weekly Wealth Review');
    expect(
      invocation.context['artifact_summary'],
      'Net worth moved 2.4% with cashflow pressure.',
    );
    expect(capturedObjectLabel, 'Weekly Wealth Review');
    expect(capturedPrefill, isNull);
  });
}
