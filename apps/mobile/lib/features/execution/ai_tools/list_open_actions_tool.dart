import 'package:naviwealth/core/ai/contracts/evidence_anchor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '_read_support.dart';

class ListOpenActionsTool implements DeviceTool {
  const ListOpenActionsTool();

  @override
  String get name => 'list_open_actions';

  @override
  String get description =>
      '列出 ExecutionOS 中尚未完成的 Action(todo/doing/blocked)。'
      '用于回答「我现在有哪些 todo / 下一步 / 阻塞项」。可选 limit。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 200, 'default': 50},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final repo = await ctx.ref.read(executionRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 200)
        : 50;
    final actions = await repo.listOpenActions(
      ownerUserId: ownerUserId,
      limit: limit,
    );
    final plans = await repo.listActivePlans(ownerUserId: ownerUserId);
    return withEvidence(
      result: <String, Object?>{
        'actions': actions
            .map((action) => executionActionJson(action, plans: plans))
            .toList(growable: false),
      },
      anchors: actions
          .take(8)
          .map(
            (action) => EvidenceAnchor(
              entityTable: 'execution_actions',
              entityId: action.id,
              label: action.title,
            ),
          ),
    );
  }
}
