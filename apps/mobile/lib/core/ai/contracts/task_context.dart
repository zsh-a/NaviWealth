/// Domain-neutral date ranges and structured device-tool signals.
library;

class DateRange {
  const DateRange({required this.fromInclusive, required this.toExclusive});

  /// ISO 8601 date or datetime; consumed by domain-local query planners.
  final String fromInclusive;
  final String toExclusive;

  Map<String, Object?> toJson() => <String, Object?>{
    'from_inclusive': fromInclusive,
    'to_exclusive': toExclusive,
  };

  factory DateRange.fromJson(Map<String, Object?> json) {
    final f = json['from_inclusive'];
    final t = json['to_exclusive'];
    return DateRange(
      fromInclusive: f is String ? f : '1970-01-01',
      toExclusive: t is String ? t : '1970-01-01',
    );
  }
}

/// 端侧 detector 输出的单条分析信号。**类名沿用"Upload"是历史**：此前
/// 这是端侧信号同步到后端 read model 的载体；删除后端 AI 后，这些条目
/// 只作为 device tool 的稳定输出 shape，供各工具复用同一套端侧 detector
/// 结果，避免 prompt grounding 和 tool 输出各自漂移。
///
/// 保留 class/字段/wire key 只为序列化稳定；如果未来改名应改成
/// `DeviceAnalyticalSignal` 之类。
class AnalyticalUpload {
  const AnalyticalUpload({
    required this.kind,
    required this.id,
    required this.payload,
  });

  /// 'recurring_pattern' / 'anomaly_flag' / 'refund_link' /
  /// 'subscription_change' 等。LLM prompt 按 kind 渲染摘要。
  final String kind;

  /// 设备约定的稳定 id —— 同 (kind, id) 重复视为 upsert。
  /// 例如 recurring_pattern 用 `'<merchant_key>|<currency>'`.
  final String id;

  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'id': id,
    'payload': payload,
  };

  factory AnalyticalUpload.fromJson(Map<String, Object?> json) {
    final k = json['kind'];
    final i = json['id'];
    final p = json['payload'];
    return AnalyticalUpload(
      kind: k is String ? k : '',
      id: i is String ? i : '',
      payload: p is Map
          ? p.map((k, v) => MapEntry(k.toString(), v))
          : const <String, Object?>{},
    );
  }
}
