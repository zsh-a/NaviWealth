/// Per-request AI Router decision + execution record.
///
/// Stored locally only — never replicated via OpLog. Drives the user-
/// visible 'AI 透明度' affordance ('未上传原始交易明细', tool count,
/// disclosure summary) and the in-app audit page. 30-day rolling
/// retention; older rows are pruned by [AiTraceStore].
library;

import 'intent.dart';
import 'privacy_budget.dart' show BudgetTier, BudgetTierWire;
import 'scoped_disclosure.dart'
    show DisclosurePurpose, DisclosurePurposeWire, UserConsent, UserConsentWire;

enum Backend { device, cloud, hybrid }

extension BackendWire on Backend {
  String get wire => switch (this) {
    Backend.device => 'device',
    Backend.cloud => 'cloud',
    Backend.hybrid => 'hybrid',
  };

  static Backend parse(String s) => switch (s) {
    'device' => Backend.device,
    'cloud' => Backend.cloud,
    'hybrid' => Backend.hybrid,
    _ => Backend.device,
  };
}

class TraceToolCall {
  const TraceToolCall({
    required this.name,
    required this.durationMs,
    required this.ok,
  });

  final String name;
  final int durationMs;
  final bool ok;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'duration_ms': durationMs,
    'ok': ok,
  };

  factory TraceToolCall.fromJson(Map<String, Object?> json) {
    final n = json['name'];
    final d = json['duration_ms'];
    final ok = json['ok'];
    return TraceToolCall(
      name: n is String ? n : '',
      durationMs: d is int ? d : 0,
      ok: ok is bool ? ok : false,
    );
  }
}

class DisclosureSummary {
  const DisclosureSummary({
    required this.purpose,
    required this.fieldsCount,
    required this.rowCount,
    required this.consent,
  });

  final DisclosurePurpose purpose;
  final int fieldsCount;
  final int rowCount;
  final UserConsent consent;

  Map<String, Object?> toJson() => <String, Object?>{
    'purpose': purpose.wire,
    'fields_count': fieldsCount,
    'row_count': rowCount,
    'consent': consent.wire,
  };

  factory DisclosureSummary.fromJson(Map<String, Object?> json) {
    final p = json['purpose'];
    final f = json['fields_count'];
    final r = json['row_count'];
    final c = json['consent'];
    return DisclosureSummary(
      purpose: p is String
          ? DisclosurePurposeWire.parse(p)
          : DisclosurePurpose.other,
      fieldsCount: f is int ? f : 0,
      rowCount: r is int ? r : 0,
      consent: c is String ? UserConsentWire.parse(c) : UserConsent.denied,
    );
  }
}

class AiTrace {
  const AiTrace({
    required this.requestId,
    required this.startedAtIso,
    required this.intent,
    required this.backend,
    required this.budgetTier,
    required this.routingReason,
    required this.usedCloud,
    required this.usedRawLedger,
    required this.totalDurationMs,
    this.disclosures = const <DisclosureSummary>[],
    this.toolCalls = const <TraceToolCall>[],
    this.staleReadModelNames = const <String>{},
  });

  final String requestId;
  final String startedAtIso;
  final IntentHint intent;
  final Backend backend;
  final BudgetTier budgetTier;

  /// Short label for why the router chose this backend
  /// ('offline_fallback', 'capability_classify', 'risk_propose', ...).
  /// Free-form for now; promoted to an enum once the matrix stabilises.
  final String routingReason;

  final bool usedCloud;

  /// True if any DisclosureRequest was answered with consent != denied.
  /// Drives the user-visible '未上传原始交易明细' badge — its inverse.
  final bool usedRawLedger;

  final int totalDurationMs;
  final List<DisclosureSummary> disclosures;
  final List<TraceToolCall> toolCalls;

  /// Read model names whose `source_hlc_watermark` was behind the
  /// device's local HLC at tool_result time. Drives the transparency
  /// badge count and feeds Phase 2's force-refresh hint on the next
  /// chat request (lib/features/ai_chat/data/providers.dart).
  final Set<String> staleReadModelNames;

  /// Count form for UI / older callers.
  int get staleReadModels => staleReadModelNames.length;

  Map<String, Object?> toJson() => <String, Object?>{
    'request_id': requestId,
    'started_at': startedAtIso,
    'intent': intent.toJson(),
    'backend': backend.wire,
    'budget_tier': budgetTier.wire,
    'routing_reason': routingReason,
    'used_cloud': usedCloud,
    'used_raw_ledger': usedRawLedger,
    'total_duration_ms': totalDurationMs,
    'disclosures': disclosures.map((d) => d.toJson()).toList(growable: false),
    'tool_calls': toolCalls.map((t) => t.toJson()).toList(growable: false),
    if (staleReadModelNames.isNotEmpty)
      'stale_read_model_names': staleReadModelNames.toList(growable: false),
  };

  factory AiTrace.fromJson(Map<String, Object?> json) {
    final id = json['request_id'];
    final ts = json['started_at'];
    final it = json['intent'];
    final bk = json['backend'];
    final bt = json['budget_tier'];
    final rr = json['routing_reason'];
    final uc = json['used_cloud'];
    final ul = json['used_raw_ledger'];
    final td = json['total_duration_ms'];
    final stale = json['stale_read_model_names'];
    final staleNames = <String>{};
    if (stale is List) {
      for (final e in stale) {
        if (e is String && e.isNotEmpty) staleNames.add(e);
      }
    }
    return AiTrace(
      requestId: id is String ? id : '',
      startedAtIso: ts is String ? ts : '',
      intent: it is Map
          ? IntentHint.fromJson(_strKeyed(it))
          : const IntentHint(
              capability: Capability.analyze,
              risk: RiskLevel.info,
            ),
      backend: bk is String ? BackendWire.parse(bk) : Backend.device,
      budgetTier: bt is String
          ? BudgetTierWire.parse(bt)
          : BudgetTier.standard,
      routingReason: rr is String ? rr : '',
      usedCloud: uc is bool ? uc : false,
      usedRawLedger: ul is bool ? ul : false,
      totalDurationMs: td is int ? td : 0,
      disclosures: _list(json['disclosures'], DisclosureSummary.fromJson),
      toolCalls: _list(json['tool_calls'], TraceToolCall.fromJson),
      staleReadModelNames: staleNames,
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
