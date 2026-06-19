/// Per-request, dynamically-generated portion of [ContextPack].
///
/// Re-built for each device chat turn; never cached. This is where the
/// device places route, intent, and recent-signal hints. Always small
/// enough to fit alongside [BaseContext] under the active [PrivacyBudget].
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
  /// On its own it is not a usable entity id; callers need domain-specific
  /// routing metadata to turn it into a deep link or evidence anchor.
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
      severity: s is String ? SignalSeverityWire.parse(s) : SignalSeverity.info,
      summaryZh: sum is String ? sum : '',
      detailRef: ref is String ? ref : null,
    );
  }
}

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

class TaskContext {
  const TaskContext({
    required this.route,
    required this.intent,
    this.signals = const <RecentSignal>[],
  });

  final RouteContext route;
  final IntentHint intent;
  final List<RecentSignal> signals;

  Map<String, Object?> toJson() => <String, Object?>{
    'route': route.toJson(),
    'intent': intent.toJson(),
    'signals': signals.map((s) => s.toJson()).toList(growable: false),
  };

  factory TaskContext.fromJson(Map<String, Object?> json) {
    final route = json['route'];
    final intent = json['intent'];
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
