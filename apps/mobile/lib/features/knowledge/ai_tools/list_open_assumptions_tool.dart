/// `list_open_assumptions` — KnowledgeOS device tool
/// (`docs/knowledgeos-domain.md` §4).
///
/// Feeds the AssumptionAgent and Review tab. Returns active (non-falsified
/// non-retired) assumptions with days-since-last-verify so the model can
/// flag the shaky ones.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';

class ListOpenAssumptionsTool implements DeviceTool {
  const ListOpenAssumptionsTool();

  @override
  String get name => 'list_open_assumptions';

  @override
  String get description =>
      '列出所有 status=active 的 KnowledgeOS Assumption,每条带 statement / confidence / '
      'scope / source_decision_ids (反向查找哪些决策引用了它) / last_verified_at / '
      'days_since_verify。可选用 confidence_max 过滤,例如 confidence_max=0.5 拿"低置信开放假设"。'
      '用途:Assumption Agent / Review tab / 决策前的预校验。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'confidence_max': {
        'type': 'number',
        'minimum': 0,
        'maximum': 1,
        'description': '只返回 confidence ≤ 该值的开放假设。',
      },
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 200, 'default': 50},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final repo = await ctx.ref.read(knowledgeRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final confidenceMax = (input['confidence_max'] is num)
        ? (input['confidence_max'] as num).toDouble()
        : null;
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 200)
        : 50;

    final assumptions = await repo.listOpenAssumptions(
      ownerUserId: ownerUserId,
      confidenceMax: confidenceMax,
    );

    // Build reverse-lookup: decisions referencing each assumption.
    final decisions = await repo.listDecisions(
      ownerUserId: ownerUserId,
      limit: 500,
    );
    final referencingByAssumptionId = <String, List<String>>{};
    for (final d in decisions) {
      for (final aid in d.assumptionIds) {
        referencingByAssumptionId.putIfAbsent(aid, () => <String>[]).add(d.id);
      }
    }

    final now = DateTime.now().toUtc();
    final out = assumptions
        .take(limit)
        .map((a) {
          return <String, Object?>{
            'id': a.id,
            'statement': a.statement,
            'confidence': a.confidence,
            'scope': a.scope,
            'source_decision_ids':
                referencingByAssumptionId[a.id] ?? const <String>[],
            'last_verified_at': a.lastVerifiedAt?.toUtc().toIso8601String(),
            'days_since_verify': a.daysSinceVerify(now),
          };
        })
        .toList(growable: false);

    return <String, Object?>{'assumptions': out};
  }
}
