/// Freshness 元数据 — Cloud AI Read Models 工具返回的版本/水印信息。
///
/// 文档: `docs/ai-architecture.md` §4.3.5。Rust 镜像:
/// `apps/backend/src/ai/read_models/freshness.rs::Freshness`。
///
/// 工具调用返回的 `output` 里如果含 `freshness` 字段，端侧可以:
///  1. 比对 `sourceHlcWatermark` 与本地最新 HLC，落后则触发
///     `request_freshness_refresh` (Phase 2 兜底通道)。
///  2. 校验 `schemaVersion` / `calculationVersion` —— 不匹配时旧缓存
///     不能与新结果混用。
///  3. 写入 AiTrace 的 disclosure 摘要做事后审计。
library;

class Freshness {
  const Freshness({
    required this.readModel,
    required this.sourceHlcWatermark,
    required this.refreshedAt,
    required this.schemaVersion,
    required this.calculationVersion,
  });

  final String readModel;
  final String sourceHlcWatermark;
  final String refreshedAt;
  final int schemaVersion;
  final int calculationVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'read_model': readModel,
    'source_hlc_watermark': sourceHlcWatermark,
    'refreshed_at': refreshedAt,
    'schema_version': schemaVersion,
    'calculation_version': calculationVersion,
  };

  factory Freshness.fromJson(Map<String, Object?> json) {
    final rm = json['read_model'];
    final wm = json['source_hlc_watermark'];
    final ra = json['refreshed_at'];
    final sv = json['schema_version'];
    final cv = json['calculation_version'];
    return Freshness(
      readModel: rm is String ? rm : '',
      sourceHlcWatermark: wm is String ? wm : '',
      refreshedAt: ra is String ? ra : '',
      schemaVersion: sv is int ? sv : 0,
      calculationVersion: cv is int ? cv : 0,
    );
  }

  /// Pull a [Freshness] out of a tool_result `output` payload. Returns
  /// `null` when the payload doesn't carry one (legacy tools that don't
  /// read from a Read Model).
  static Freshness? tryFromOutput(Object? output) {
    if (output is! Map) return null;
    final raw = output['freshness'];
    if (raw is! Map) return null;
    return Freshness.fromJson(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
  }
}
