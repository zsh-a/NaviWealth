import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../features/fire/data/fire_providers.dart';
import '../../../../../features/fire/domain/fire_state.dart';
import 'device_tool.dart';

/// `get_fire_state` — return the deterministic FIRE OS state read model.
///
/// Pure read. The state engine runs in pure Dart (`fire_state_service`),
/// so the AI gets ground-truth metrics with no LLM-derived numbers in
/// the result. AI explanations downstream of this must cite the JSON
/// fields verbatim.
class GetFireStateTool implements DeviceTool {
  const GetFireStateTool();

  @override
  String get name => 'get_fire_state';

  @override
  String get description =>
      '返回当前 FIRE OS 状态(安全等级 / 提取率 / 现金桶覆盖 / FIRE ETA / 推荐动作)。'
      '所有数字均为本地确定性计算结果——请用 JSON 字段原样转述,不要凭直觉改写。'
      '`safety_level` 取值:safe / cautious / danger / unconfigured。'
      '`withdrawal_rate` 为 null 表示有支出但无可投资资产(危险);为有限数时取与 `safe_withdrawal_rate` 比较即可。'
      '出现 `unmapped_holdings` 时请提醒用户:这些资产暂未纳入桶,不参与提取/现金桶计算。';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final state = await _awaitState(ctx);
    if (state == null) {
      return <String, Object?>{
        'error': 'fire_state_unavailable',
        'code': 'unavailable',
        'note': 'snapshot not ready or no data',
      };
    }
    return state.toJson();
  }
}

Future<FireState?> _awaitState(DeviceToolContext ctx) async {
  final async = ctx.ref.read(fireStateProvider);
  return async.whenOrNull(data: (s) => s);
}
