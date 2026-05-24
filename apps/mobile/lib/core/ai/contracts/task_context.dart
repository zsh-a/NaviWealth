/// Per-request, dynamically-generated portion of [ContextPack].
///
/// Re-built every router invocation; never cached. This is where the
/// device places intent-specific signals, scoped aggregates, and (in
/// later phases) RAG hits. Always small enough to fit alongside
/// [BaseContext] under the active [PrivacyBudget].
library;

import 'intent.dart';

class RouteContext {
  const RouteContext({required this.path, required this.area});

  /// go_router path of the active surface (e.g. '/expenses', '/fire').
  final String path;

  /// Coarse functional area derived from [path]: 'expense',
  /// 'investment', 'fire', 'home', 'settings', 'unknown'. Stable enum
  /// space for the planner to reason about regardless of routing
  /// changes.
  final String area;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'area': area,
  };

  factory RouteContext.fromJson(Map<String, Object?> json) {
    final p = json['path'];
    final a = json['area'];
    return RouteContext(
      path: p is String ? p : '/',
      area: a is String ? a : 'unknown',
    );
  }
}

enum SignalKind {
  spendingSpike,
  subscriptionPriceUp,
  refundUnmatched,
  depositMaturing,
  fireMilestone,
  cashflowAnomaly,
  other,
}

extension SignalKindWire on SignalKind {
  String get wire => switch (this) {
    SignalKind.spendingSpike => 'spending_spike',
    SignalKind.subscriptionPriceUp => 'subscription_price_up',
    SignalKind.refundUnmatched => 'refund_unmatched',
    SignalKind.depositMaturing => 'deposit_maturing',
    SignalKind.fireMilestone => 'fire_milestone',
    SignalKind.cashflowAnomaly => 'cashflow_anomaly',
    SignalKind.other => 'other',
  };

  static SignalKind parse(String s) => switch (s) {
    'spending_spike' => SignalKind.spendingSpike,
    'subscription_price_up' => SignalKind.subscriptionPriceUp,
    'refund_unmatched' => SignalKind.refundUnmatched,
    'deposit_maturing' => SignalKind.depositMaturing,
    'fire_milestone' => SignalKind.fireMilestone,
    'cashflow_anomaly' => SignalKind.cashflowAnomaly,
    _ => SignalKind.other,
  };
}

enum SignalSeverity { info, warn, critical }

extension SignalSeverityWire on SignalSeverity {
  String get wire => switch (this) {
    SignalSeverity.info => 'info',
    SignalSeverity.warn => 'warn',
    SignalSeverity.critical => 'critical',
  };

  static SignalSeverity parse(String s) => switch (s) {
    'info' => SignalSeverity.info,
    'warn' => SignalSeverity.warn,
    'critical' => SignalSeverity.critical,
    _ => SignalSeverity.info,
  };
}

class RecentSignal {
  const RecentSignal({
    required this.kind,
    required this.severity,
    required this.summaryZh,
    this.detailRef,
  });

  final SignalKind kind;
  final SignalSeverity severity;
  final String summaryZh;

  /// Opaque pointer back to a Drift row (e.g. anomaly id, maturity id).
  /// The cloud may reference this inside a DisclosureRequest; on its
  /// own it is not a usable entity id.
  final String? detailRef;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.wire,
    'severity': severity.wire,
    'summary_zh': summaryZh,
    if (detailRef != null) 'detail_ref': detailRef,
  };

  factory RecentSignal.fromJson(Map<String, Object?> json) {
    final k = json['kind'];
    final s = json['severity'];
    final sum = json['summary_zh'];
    final ref = json['detail_ref'];
    return RecentSignal(
      kind: k is String ? SignalKindWire.parse(k) : SignalKind.other,
      severity: s is String
          ? SignalSeverityWire.parse(s)
          : SignalSeverity.info,
      summaryZh: sum is String ? sum : '',
      detailRef: ref is String ? ref : null,
    );
  }
}

/// Phase 4 placeholder; the type is defined now so the wire schema is
/// stable when semantic memory ships.
class SemanticHit {
  const SemanticHit({
    required this.source,
    required this.title,
    required this.excerpt,
    required this.score,
  });

  final String source;
  final String title;
  final String excerpt;
  final double score;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'title': title,
    'excerpt': excerpt,
    'score': score,
  };

  factory SemanticHit.fromJson(Map<String, Object?> json) {
    final src = json['source'];
    final ttl = json['title'];
    final exc = json['excerpt'];
    final scr = json['score'];
    return SemanticHit(
      source: src is String ? src : '',
      title: ttl is String ? ttl : '',
      excerpt: exc is String ? exc : '',
      score: scr is num ? scr.toDouble() : 0,
    );
  }
}

class DateRange {
  const DateRange({required this.fromInclusive, required this.toExclusive});

  /// ISO 8601 date or datetime; consumed by the device skill layer
  /// (`finance_query_plan` / `query_plan_executor`).
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

/// 端侧 detector 输出的单条分析信号。**类名沿用"Upload"是历史**：W-D7
/// 前这是端→云上报、由后端镜像入 read model；W-D7 删除后端 AI 后，这些条目
/// 现在的唯一用途是**预注入 device LLM 的 prompt**（在 LLM 调对应 device tool
/// 之前给它一个聚合摘要，减少首轮 tool round）。
///
/// 保留 class/字段/wire key（`analytical_uploads`）只为序列化稳定；如果未来
/// 改名应改成 `PromptAnalyticalSignal` 之类。是否保留这层预注入待测量
/// （`docs/ai-boundary-audit.md` 批 D）。
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

class TaskContext {
  const TaskContext({
    required this.route,
    required this.intent,
    this.signals = const <RecentSignal>[],
    this.analyticalUploads = const <AnalyticalUpload>[],
    this.deviceHlc,
  });

  final RouteContext route;
  final IntentHint intent;
  final List<RecentSignal> signals;

  /// 端侧 detector 信号（recurring_pattern / anomaly_flag / refund_link /
  /// transfer_link / subscription_change / investment_performance）预注入
  /// 到 device LLM 的 prompt。类名见 [AnalyticalUpload]——"Upload"是历史命名，
  /// 已无 upload 行为。
  final List<AnalyticalUpload> analyticalUploads;

  /// 端侧本地最新 HLC（同 syncLocalHlcProvider 的字符串形式），用作本批
  /// analyticalUploads 的时戳，让 LLM 知道这批摘要是多久前的快照。
  /// Null = 没上报或未取到 HLC。
  final String? deviceHlc;

  Map<String, Object?> toJson() => <String, Object?>{
    'route': route.toJson(),
    'intent': intent.toJson(),
    'signals': signals.map((s) => s.toJson()).toList(growable: false),
    if (analyticalUploads.isNotEmpty)
      'analytical_uploads':
          analyticalUploads.map((u) => u.toJson()).toList(growable: false),
    if (deviceHlc != null && deviceHlc!.isNotEmpty) 'device_hlc': deviceHlc,
  };

  factory TaskContext.fromJson(Map<String, Object?> json) {
    final route = json['route'];
    final intent = json['intent'];
    final dh = json['device_hlc'];
    return TaskContext(
      route: route is Map
          ? RouteContext.fromJson(_strKeyed(route))
          : const RouteContext(path: '/', area: 'unknown'),
      intent: intent is Map
          ? IntentHint.fromJson(_strKeyed(intent))
          : const IntentHint(
              capability: Capability.analyze,
              risk: RiskLevel.info,
            ),
      signals: _list(json['signals'], RecentSignal.fromJson),
      analyticalUploads: _list(
        json['analytical_uploads'],
        AnalyticalUpload.fromJson,
      ),
      deviceHlc: dh is String ? dh : null,
    );
  }
}

Map<String, Object?> _strKeyed(Map<Object?, Object?> raw) =>
    raw.map((k, v) => MapEntry(k.toString(), v));

List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) f) {
  if (raw is! List) return <T>[];
  final out = <T>[];
  for (final item in raw) {
    if (item is Map) {
      out.add(f(_strKeyed(item)));
    }
  }
  return out;
}
