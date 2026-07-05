/// `list_active_principles` — KnowledgeOS device tool.
///
/// Provides the active Principle set used by scheduled KnowledgeOS agents.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/knowledge_models.dart';

class ListActivePrinciplesTool implements DeviceTool {
  const ListActivePrinciplesTool();

  @override
  String get name => 'list_active_principles';

  @override
  String get description =>
      '列出 KnowledgeOS 当前 active principles。'
      '返回 id / statement / rationale_md / scope / declared_at。'
      '用途: ContradictionAgent value-alignment 检查。';

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
    final principles = await repo.listActivePrinciples(
      ownerUserId: ownerUserId,
    );
    return <String, Object?>{
      'principles': principles
          .take(limit)
          .map(_principleRecord)
          .toList(growable: false),
    };
  }

  static Map<String, Object?> _principleRecord(KnowledgePrinciple principle) {
    return <String, Object?>{
      'id': principle.id,
      'statement': principle.statement,
      'rationale_md': principle.rationaleMd,
      'scope': principle.scope,
      'declared_at': principle.declaredAt.toUtc().toIso8601String(),
    };
  }
}
