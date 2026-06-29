/// `list_triage_decisions` — KnowledgeOS device tool.
///
/// Provides the bounded decision context used by `InboxTriageAgent` when it
/// decides whether an inbox note should link to an existing Decision.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/knowledge_models.dart';

class ListTriageDecisionsTool implements DeviceTool {
  const ListTriageDecisionsTool();

  @override
  String get name => 'list_triage_decisions';

  @override
  String get description =>
      '列出 InboxTriageAgent 关联候选用的最近 KnowledgeOS decisions。'
      '返回 id / question / selected / status / decided_at。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'limit': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 200,
        'default': 200,
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 200)
        : 200;
    final decisions = await repo.listDecisions(
      ownerUserId: ownerUserId,
      limit: limit,
    );
    return <String, Object?>{
      'decisions': decisions.map(_decisionRecord).toList(growable: false),
    };
  }

  static Map<String, Object?> _decisionRecord(KnowledgeDecision decision) {
    return <String, Object?>{
      'id': decision.id,
      'question': decision.question,
      'selected': decision.selectedLabel,
      'status': decision.status.wire,
      'decided_at': decision.decidedAt.toUtc().toIso8601String(),
    };
  }
}
