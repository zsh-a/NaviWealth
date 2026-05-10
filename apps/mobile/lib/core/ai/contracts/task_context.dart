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

class TaskContext {
  const TaskContext({
    required this.route,
    required this.intent,
    this.signals = const <RecentSignal>[],
    this.retrieved = const <SemanticHit>[],
    this.aggregates = const <ScopedAggregate>[],
  });

  final RouteContext route;
  final IntentHint intent;
  final List<RecentSignal> signals;
  final List<SemanticHit> retrieved;
  final List<ScopedAggregate> aggregates;

  Map<String, Object?> toJson() => <String, Object?>{
    'route': route.toJson(),
    'intent': intent.toJson(),
    'signals': signals.map((s) => s.toJson()).toList(growable: false),
    'retrieved': retrieved.map((h) => h.toJson()).toList(growable: false),
    'aggregates': aggregates.map((a) => a.toJson()).toList(growable: false),
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
      retrieved: _list(json['retrieved'], SemanticHit.fromJson),
      aggregates: _list(json['aggregates'], ScopedAggregate.fromJson),
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
