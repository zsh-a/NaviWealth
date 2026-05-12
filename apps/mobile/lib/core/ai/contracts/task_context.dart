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

  /// ISO 8601 date or datetime; the cloud parses both forms.
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

class ScopedAggregate {
  const ScopedAggregate({
    required this.label,
    required this.amountMinor,
    required this.currency,
    required this.range,
    this.rowCount,
  });

  final String label;
  final String amountMinor;
  final String currency;
  final DateRange range;
  final int? rowCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'amount_minor': amountMinor,
    'currency': currency,
    'range': range.toJson(),
    if (rowCount != null) 'row_count': rowCount,
  };

  factory ScopedAggregate.fromJson(Map<String, Object?> json) {
    final lbl = json['label'];
    final amt = json['amount_minor'];
    final cur = json['currency'];
    final rng = json['range'];
    final rc = json['row_count'];
    return ScopedAggregate(
      label: lbl is String ? lbl : '',
      amountMinor: amt is String ? amt : '0',
      currency: cur is String ? cur : 'USD',
      range: rng is Map
          ? DateRange.fromJson(_strKeyed(rng))
          : const DateRange(
              fromInclusive: '1970-01-01',
              toExclusive: '1970-01-01',
            ),
      rowCount: rc is int ? rc : null,
    );
  }
}

/// 端侧主动给云端的「这些 read model 落后我了，dispatch 前请重投」
/// 提示。docs/ai-architecture.md §4.2 freshness gate Phase 2 闭环。
///
/// 触发路径：上一轮 chat 完结时，AiTrace 收集了 stale read_model 名 →
/// `pendingFreshnessHintProvider` 累计 → 下一次 prep 注入此 hint →
/// 云端 routes/ai.rs 在 dispatch 前 `clear_freshness_meta` 强制
/// `ensure_fresh` 重算。Hint 单向、幂等、消费后清空。
class FreshnessHint {
  const FreshnessHint({
    this.forceRefreshReadModels = const <String>[],
    this.lastLocalHlc,
  });

  /// Read model 名（如 `monthly_spend_by_category`）。云端逐一失效
  /// 对应 freshness_meta 行；不认识的名字直接忽略。
  final List<String> forceRefreshReadModels;

  /// Wave 32 — 端侧此次 chat 时的 localHlc 字符串。云端可用作 freshness
  /// 比较的真值水位（之前依赖 TaskContext.deviceHlc，但语义上 HLC
  /// 属于 freshness 协议，挪进来后 TaskContext.deviceHlc 仅作为
  /// analytical_uploads 的批次戳）。
  /// `null` = 端未提供（早期 client）。
  final String? lastLocalHlc;

  bool get isEmpty =>
      forceRefreshReadModels.isEmpty && (lastLocalHlc == null);

  Map<String, Object?> toJson() => <String, Object?>{
    'force_refresh_read_models': forceRefreshReadModels,
    if (lastLocalHlc != null) 'last_local_hlc': lastLocalHlc,
  };

  factory FreshnessHint.fromJson(Map<String, Object?> json) {
    final raw = json['force_refresh_read_models'];
    final names = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String && e.isNotEmpty) names.add(e);
      }
    }
    final hlc = json['last_local_hlc'];
    return FreshnessHint(
      forceRefreshReadModels: names,
      lastLocalHlc: hlc is String && hlc.isNotEmpty ? hlc : null,
    );
  }
}

/// 端→云单条分析上报。docs/ai-architecture.md §4.3.3 Analytical 层
/// 的端侧投影：端是唯一计算者，云端只镜像 device 产物，避免 Dart/Rust
/// 启发式逻辑双份漂移。
class AnalyticalUpload {
  const AnalyticalUpload({
    required this.kind,
    required this.id,
    required this.payload,
  });

  /// 'recurring_pattern' / 'anomaly_flag' / 'refund_link' /
  /// 'subscription_change' 等。后端按 kind 路由到对应 read model 表。
  final String kind;

  /// 设备约定的稳定 id —— 同 (kind, id) 重复上报视为 upsert。
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
    this.retrieved = const <SemanticHit>[],
    this.aggregates = const <ScopedAggregate>[],
    this.freshnessHint,
    this.analyticalUploads = const <AnalyticalUpload>[],
    this.deviceHlc,
  });

  final RouteContext route;
  final IntentHint intent;
  final List<RecentSignal> signals;
  final List<SemanticHit> retrieved;
  final List<ScopedAggregate> aggregates;
  final FreshnessHint? freshnessHint;

  /// 端侧 detector 上报：每条 kind=recurring_pattern/anomaly_flag/...
  /// 后端镜像入对应 device-sourced read model。
  final List<AnalyticalUpload> analyticalUploads;

  /// 端侧本地最新 HLC（同 syncLocalHlcProvider 的字符串形式），作为本
  /// 批 analytical_uploads 的 source_hlc_watermark。Null = 没上报。
  final String? deviceHlc;

  Map<String, Object?> toJson() => <String, Object?>{
    'route': route.toJson(),
    'intent': intent.toJson(),
    'signals': signals.map((s) => s.toJson()).toList(growable: false),
    'retrieved': retrieved.map((h) => h.toJson()).toList(growable: false),
    'aggregates': aggregates.map((a) => a.toJson()).toList(growable: false),
    if (freshnessHint != null && !freshnessHint!.isEmpty)
      'freshness_hint': freshnessHint!.toJson(),
    if (analyticalUploads.isNotEmpty)
      'analytical_uploads':
          analyticalUploads.map((u) => u.toJson()).toList(growable: false),
    if (deviceHlc != null && deviceHlc!.isNotEmpty) 'device_hlc': deviceHlc,
  };

  factory TaskContext.fromJson(Map<String, Object?> json) {
    final route = json['route'];
    final intent = json['intent'];
    final hint = json['freshness_hint'];
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
      retrieved: _list(json['retrieved'], SemanticHit.fromJson),
      aggregates: _list(json['aggregates'], ScopedAggregate.fromJson),
      freshnessHint: hint is Map
          ? FreshnessHint.fromJson(_strKeyed(hint))
          : null,
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
