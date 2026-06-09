/// `get_recovery_signal` — HealthOS device tool
/// (`docs/healthos-domain.md` §4, D-2.4).
///
/// Delegates to [RecoveryScorer] for the scoring math.
library;

import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../data/recovery_scorer.dart';
import '../domain/health_metric.dart';
import '../domain/health_metric_kind.dart';

class GetRecoverySignalTool implements DeviceTool {
  const GetRecoverySignalTool();

  @override
  String get name => 'get_recovery_signal';

  @override
  String get description =>
      '返回综合恢复信号 (0–100 分) + 等级 (rested / balanced / strained / '
      'insufficient_data) + 原始输入 (最近 HRV / 最近平均睡眠时长 / 最近 RHR / 最近 VO₂max)。'
      '算法:取过去 7 天 (recent) 和过去 7-28 天 (baseline) 的 HRV / sleep / RHR / VO₂max 均值,'
      '每项按 recent vs baseline 偏离度评分 (HRV ↑ 加分, RHR ↑ 扣分, VO₂max ↑ 加分, 睡眠 ≥ 7h 加分),'
      '可用项算术平均后裁剪到 0–100。'
      '基线 < 5 天数据时返回 insufficient_data,模型应回避"推 / 减"建议。'
      '适合场景:"今天该不该重训"/"我恢复怎么样"/"我状态可以做高强度吗"。'
      '不是医学诊断,仅供日常作息判断。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{},
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final repo = await ctx.ref.read(healthMetricRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();

    final hrv = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.hrvDaily,
      limit: 35,
    );
    final sleep = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.sleepSession,
      limit: 50,
    );
    final rhr = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.rhrDaily,
      limit: 35,
    );
    final vo2 = await repo.listByKind(
      ownerUserId: ownerUserId,
      kind: HealthMetricKind.vo2Max,
      limit: 35,
    );

    return shape(hrv: hrv, sleep: sleep, rhr: rhr, vo2Max: vo2);
  }

  /// Pure shaper — delegates to [RecoveryScorer].
  static Map<String, Object?> shape({
    required List<HealthMetric> hrv,
    required List<HealthMetric> sleep,
    required List<HealthMetric> rhr,
    List<HealthMetric> vo2Max = const <HealthMetric>[],
    DateTime? now,
  }) {
    const scorer = RecoveryScorer();
    final result = scorer.score(
      hrv: hrv,
      sleep: sleep,
      rhr: rhr,
      vo2Max: vo2Max,
      now: now,
    );

    if (!result.hasScore) {
      return <String, Object?>{
        'score': null,
        'verdict': result.verdict,
        'inputs': result.inputs,
        'note': 'Health data insufficient for recovery scoring.',
      };
    }

    return <String, Object?>{
      'score': result.score,
      'verdict': result.verdict,
      'inputs': result.inputs,
    };
  }
}
