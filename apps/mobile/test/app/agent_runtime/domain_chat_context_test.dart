import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/overrides/agent_runtime_app_overrides.dart';
import 'package:naviwealth/core/ai/composition/ai_context.dart';
import 'package:naviwealth/core/ai/composition/system_prompt_blocks.dart';
import 'package:naviwealth/core/ai/local/memory/providers.dart';
import 'package:naviwealth/core/ai/runtime/agent_runtime/agent_runtime_context_block.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/features/ai_chat/data/chat_context_block_prep.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart';

const _request = ChatContextPrepRequest(
  ownerUserId: 'u1',
  sessionId: 's1',
  turnId: 't1',
  userMessage: 'help with the current page',
);

AgentRuntimeContextBlock _block(DomainScope scope) => AgentRuntimeContextBlock(
  id: '${scope.wire}:summary',
  kind: AgentRuntimeContextBlockKind.resource,
  source: '${scope.wire}.current_state',
  content: const {'summary': 'local facts'},
);

ProviderContainer _container(AiContext context, List<DomainPack> packs) {
  return ProviderContainer(
    overrides: [
      ...agentRuntimeAppProviderOverrides(),
      activeDomainPacksProvider.overrideWithValue(packs),
      aiContextProvider.overrideWith((ref) => context),
      assembledSystemPromptProvider.overrideWithValue('Active OS rules'),
      contextBuilderProvider.overrideWith((ref) async {
        throw StateError('memory unavailable');
      }),
    ],
  );
}

void main() {
  for (final scope in [
    DomainScope.health,
    DomainScope.knowledge,
    DomainScope.execution,
  ]) {
    test(
      '${scope.wire} chat never invokes Finance context retrieval',
      () async {
        var financeReads = 0;
        final container = _container(
          AiContext(path: '/${scope.wire}', domain: scope),
          [
            DomainPack(
              scope: DomainScope.finance,
              ai: DomainAiContribution(
                chatContextBuilder: (ref, context) async {
                  financeReads++;
                  throw StateError('Finance store unavailable');
                },
              ),
            ),
            DomainPack(
              scope: scope,
              ai: DomainAiContribution(
                chatContextBuilder: (ref, context) async => [_block(scope)],
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final blocks = await container.read(chatContextBlockPrepProvider)!(
          _request,
        );

        expect(financeReads, 0);
        expect(blocks.map((block) => block.id), [
          'naviwealth:system_instructions',
          '${scope.wire}:summary',
        ]);
        expect(blocks.first.content, contains('Active OS rules'));
      },
    );
  }

  test(
    'Finance chat retains its own facts when memory retrieval fails',
    () async {
      final container = _container(
        const AiContext(path: '/plan/fire', domain: DomainScope.finance),
        [
          DomainPack(
            scope: DomainScope.finance,
            ai: DomainAiContribution(
              chatContextBuilder: (ref, context) async => [
                _block(DomainScope.finance),
              ],
            ),
          ),
          DomainPack(
            scope: DomainScope.health,
            ai: DomainAiContribution(
              chatContextBuilder: (ref, context) async => [
                _block(DomainScope.health),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final blocks = await container.read(chatContextBlockPrepProvider)!(
        _request,
      );

      expect(blocks.map((block) => block.id), [
        'naviwealth:system_instructions',
        'finance:summary',
      ]);
    },
  );

  test('global chat isolates failing and absent domain contributors', () async {
    final container = _container(const AiContext(domain: null, path: '/life'), [
      DomainPack(
        scope: DomainScope.finance,
        ai: DomainAiContribution(
          chatContextBuilder: (ref, context) async =>
              throw StateError('offline'),
        ),
      ),
      DomainPack(
        scope: DomainScope.knowledge,
        ai: DomainAiContribution(
          chatContextBuilder: (ref, context) async => [
            _block(DomainScope.knowledge),
          ],
        ),
      ),
      const DomainPack(scope: DomainScope.execution),
    ]);
    addTearDown(container.dispose);

    final blocks = await container.read(chatContextBlockPrepProvider)!(
      _request,
    );

    expect(blocks.map((block) => block.id), [
      'naviwealth:system_instructions',
      'knowledge:summary',
    ]);
  });
}
