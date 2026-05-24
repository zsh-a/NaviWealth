/// `get_anomaly_flags` — device port (§4.6 W-D4.3, Analytical layer).
///
/// Schema + description verbatim from
/// `apps/backend/src/ai/tools/get_anomaly_flags.rs`. Per §4.3.3 the
/// device detector is the **sole computer** — the backend
/// `anomaly_flags` read model is just a mirror of what the device
/// uploaded via `ContextPack.analytical_uploads`. So the device tool
/// calls the same detector ([expenseAnomalyInsightProvider]) through
/// the shared [analyticalAnomalyUpload] converter (the exact upload the
/// cloud mirrors) and projects it into the backend flag-row shape —
/// byte-identical, no D1, no freshness gate (§4.6.1).
library;

import '../../../../../features/expense/data/expense_anomaly_insight_provider.dart';
import '../../../contracts/task_context.dart' show AnalyticalUpload;
import 'device_tool.dart';

class GetAnomalyFlagsTool implements DeviceTool {
  const GetAnomalyFlagsTool();

  @override
  String get name => 'get_anomaly_flags';

  @override
  String get description =>
      '返回端侧 detector 检测到的支出 / 现金流异常。'
      '数据来自 AI Read Model `anomaly_flags`（Analytical 层 P1）—— '
      'device-sourced：端侧（如 expenseAnomalyInsightProvider）跑启发式 → '
      'ContextPack.analytical_uploads 上报 → 后端镜像。'
      'payload.kind 包含 monthly_spike / subscription_price_up / cashflow_anomaly 等。'
      '可选 severity_min 过滤（info ≤ warn ≤ critical）。';

  @override
  Map<String, Object?> get inputSchema => {
    'type': 'object',
    'properties': {
      'severity_min': {
        'type': 'string',
        'enum': ['info', 'warn', 'critical'],
        'description': '最低严重度（含），默认全部。',
      },
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final anomaly = ctx.ref.read(expenseAnomalyInsightProvider);
    return shape(
      analyticalAnomalyUpload(anomaly),
      severityMin: input['severity_min'] is String
          ? input['severity_min'] as String
          : null,
    );
  }

  static const _rank = {'info': 0, 'warn': 1, 'critical': 2};

  /// Pure projection of the device anomaly [AnalyticalUpload] into the
  /// backend `get_anomaly_flags` envelope. `upload == null` ⇒ no
  /// anomaly (empty result, same as the cloud "尚未上报 / 无异常" case).
  static Map<String, Object?> shape(
    AnalyticalUpload? upload, {
    String? severityMin,
  }) {
    final flags = <Map<String, Object?>>[];
    if (upload != null) {
      final payload = upload.payload;
      final severity = payload['severity'] as String?;
      // Backend only honours the three enum values; anything else =
      // no filter (matches `.filter(matches!(...))`).
      final min = _rank.containsKey(severityMin) ? severityMin : null;
      final passes = min == null || (_rank[severity] ?? 0) >= (_rank[min] ?? 0);
      if (passes) {
        flags.add(<String, Object?>{
          'id': upload.id,
          'category': payload['category'],
          'kind': payload['kind'],
          'delta_pct': payload['delta_pct'],
          'severity': severity,
          'detected_at': payload['detected_at'],
          'payload': payload,
        });
      }
    }
    return <String, Object?>{
      'flags': flags,
      'count': flags.length,
      'source': 'device_analytical_read_model',
      'note':
          'device-sourced：端侧 detector 检测，通过 ContextPack.analytical_uploads 上报。'
          '空结果可能是端侧还没上报 / 没有异常。',
    };
  }
}
