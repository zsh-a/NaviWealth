import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_envelope.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/local/embedding/embedder.dart';
import 'package:naviwealth/core/ai/local/memory/event_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_access_policy.dart';
import 'package:naviwealth/core/ai/local/memory/memory_candidate_store.dart';
import 'package:naviwealth/core/ai/local/memory/memory_proposal_applier.dart';
import 'package:naviwealth/core/ai/local/memory/memory_runtime.dart';
import 'package:naviwealth/core/ai/local/memory/memory_store.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_context_block.dart';
import 'package:naviwealth/core/auth/auth_session.dart';
import 'package:naviwealth/core/lifeos/personal_profile/personal_profile_store.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';
import 'package:naviwealth/features/ai_chat/data/ai_chat_api_client.dart';
import 'package:naviwealth/features/ai_chat/data/chat_history_store.dart';
import 'package:naviwealth/features/ai_chat/data/chat_repository.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/ui/proposals/propose_card.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  testWidgets(
    'cancel rejects staged memory and persists interaction response',
    (tester) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final candidateStore = SqliteMemoryCandidateStore(db: db);
      final runtime = MemoryRuntime(
        embedder: StubEmbedder(),
        memoryStore: SqliteMemoryStore(db: db),
        eventStore: SqliteEventStore(db: db),
      );
      final applier = MemoryProposalApplier(
        ownerUserId: 'user-1',
        runtime: runtime,
        profileStore: SqlitePersonalProfileStore(db),
        candidateStore: candidateStore,
        accessPolicy: MemoryAccessPolicy.allowPrefixes(const <String>[
          'user_confirmed_ai',
        ]),
        activeProfileDomainScopes: const <String>{},
      );
      const payload = <String, Object?>{
        'candidate_id': 'candidate-1',
        'target_type': 'memory',
        'operation': 'create',
        'record_id': 'memory-1',
        'memory_kind': 'semantic',
        'title': '本地优先',
        'summary': '用户偏好本地优先。',
        'scope': '*',
        'entities': <String>[],
        'memory_payload': <String, Object?>{},
        'importance': 0.8,
        'reason': '长期偏好',
      };
      final now = DateTime.utc(2026, 7, 23);
      await candidateStore.insert(
        MemoryChangeCandidate(
          id: 'candidate-1',
          proposalId: 'proposal-1',
          ownerUserId: 'user-1',
          operation: MemoryCandidateOperation.create,
          targetType: MemoryCandidateTargetType.memory,
          status: MemoryCandidateStatus.pending,
          payload: payload,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final output = readyPlan(
        proposalId: 'proposal-1',
        kind: kMemoryChangeProposalKind,
        summaryZh: '建议记住本地优先',
        payload: payload,
      );
      final plan = ProposalPlan.tryParse(output)!;
      final invocation = ToolInvocation(
        id: 'tool-1',
        name: 'propose_memory',
        input: const <String, Object?>{},
        output: output,
      );
      final message = ChatMessage(
        id: 'message-1',
        sessionId: 'session-1',
        ownerUserId: 'user-1',
        role: ChatRole.assistant,
        content: '',
        status: ChatMessageStatus.complete,
        toolCalls: <ToolInvocation>[invocation],
        createdAt: now,
      );
      final history = ChatHistoryStore(db);
      addTearDown(history.dispose);
      final repo = ChatRepository(
        store: history,
        api: _NoopApi(),
        sessionReader: () => null,
      );
      await history.insertSession(
        ChatSession(
          id: 'session-1',
          ownerUserId: 'user-1',
          title: 'test',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await history.insertMessage(message);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatRepositoryProvider.overrideWith((ref) async => repo),
            proposalApplierProvider.overrideWith((ref) async => applier),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FTheme(
              data: FTheme.neutral.light.desktop,
              child: Scaffold(
                body: ProposeCard(
                  sessionId: 'session-1',
                  message: message,
                  invocation: invocation,
                  plan: plan,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(
        (await candidateStore.findById(
          ownerUserId: 'user-1',
          candidateId: 'candidate-1',
        ))?.status,
        MemoryCandidateStatus.rejected,
      );
      final persisted = (await history.listMessages('session-1'))
          .single
          .toolCalls
          .single;
      expect(persisted.applyState?.status, ProposalApplyStatus.cancelled);
      expect(persisted.interactionResponse?.action, AiInteractionAction.reject);
    },
  );
}

final class _NoopApi implements AiChatApiClient {
  @override
  Stream<AiChatEvent> chat({
    required AuthSession session,
    required List<WireMessage> messages,
    String? turnId,
    String? sessionId,
    String? threadId,
    String? surface,
    String? agentId,
    String? mode,
    Map<String, Object?> metadata = const <String, Object?>{},
    Map<String, Object?>? portfolioSnapshot,
    ContextPack? contextPack,
    List<AgentRuntimeContextBlock> contextBlocks =
        const <AgentRuntimeContextBlock>[],
    AgentRuntimeContextPolicy? contextPolicy,
    AiInteractionResponse? interactionResponse,
    String? model,
    CancelToken? cancelToken,
  }) async* {
    throw UnimplementedError('not used');
  }
}
