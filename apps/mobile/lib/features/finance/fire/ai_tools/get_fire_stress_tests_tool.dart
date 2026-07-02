import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';

/// `get_fire_stress_tests` — return the deterministic stress-test
/// verdicts (`runStressTests`). Pure read; AI explains, doesn't invent.
class GetFireStressTestsTool implements DeviceTool {
  const GetFireStressTestsTool();

  @override
  String get name => 'get_fire_stress_tests';

  @override
  String get description =>
      '返回 FIRE 计划在五种压力场景下的判断:市场回撤、支出上升、一次性冲击、汇率冲击、现金桶耗尽。'
      '每项包含 verdict (safe / cautious / danger)、压力后关键指标、推荐动作。'
      '请逐条解释含义,不要把多个压力测试结果混合成一句模糊的话;不要把 stress test 描述为预测,'
      '它检验的是韧性,不是涨跌方向。';

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
    final async = ctx.ref.read(fireStressTestsProvider);
    final results = async.whenOrNull(data: (r) => r);
    if (results == null) {
      return <String, Object?>{
        'error': 'stress_tests_unavailable',
        'code': 'unavailable',
      };
    }
    return <String, Object?>{
      'results': [for (final r in results) r.toJson()],
    };
  }
}
