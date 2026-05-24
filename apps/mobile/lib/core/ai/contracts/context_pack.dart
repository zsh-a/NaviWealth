/// Top-level wire contract between device and cloud planner.
///
/// `ContextPack = BaseContext (stable) + TaskContext (per-request) +
/// PrivacyBudget (size cap)`. The cloud rejects packs whose `version`
/// it doesn't know about — there is no implicit fallback.
library;

import 'dart:convert';

import 'base_context.dart';
import 'intent.dart';
import 'privacy_budget.dart';
import 'task_context.dart';

class ContextPackVersion {
  const ContextPackVersion({required this.major, required this.minor});

  final int major;
  final int minor;

  Map<String, Object?> toJson() => <String, Object?>{
    'major': major,
    'minor': minor,
  };

  factory ContextPackVersion.fromJson(Map<String, Object?> json) {
    final mj = json['major'];
    final mn = json['minor'];
    return ContextPackVersion(
      major: mj is int ? mj : 1,
      minor: mn is int ? mn : 0,
    );
  }
}

const ContextPackVersion kCurrentContextPackVersion = ContextPackVersion(
  major: 1,
  minor: 0,
);

class ContextPack {
  const ContextPack({
    required this.version,
    required this.base,
    required this.task,
    required this.budget,
  });

  final ContextPackVersion version;
  final BaseContext base;
  final TaskContext task;
  final PrivacyBudget budget;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version.toJson(),
    'base': base.toJson(),
    'task': task.toJson(),
    'budget': budget.toJson(),
  };

  factory ContextPack.fromJson(Map<String, Object?> json) {
    final v = json['version'];
    final b = json['base'];
    final t = json['task'];
    final bg = json['budget'];
    return ContextPack(
      version: v is Map
          ? ContextPackVersion.fromJson(_strKeyed(v))
          : kCurrentContextPackVersion,
      base: b is Map ? BaseContext.fromJson(_strKeyed(b)) : _emptyBase,
      task: t is Map ? TaskContext.fromJson(_strKeyed(t)) : _emptyTask,
      budget: bg is Map
          ? PrivacyBudget.fromJson(_strKeyed(bg))
          : PrivacyBudget.standard,
    );
  }

  /// JSON-serialized byte size. Used by tracing and by [assertBudget].
  int get serializedByteSize => utf8.encode(jsonEncode(toJson())).length;

  /// Throws [ContextPackOversizeException] if the serialized form
  /// exceeds the budget's byte cap. Compressors must call this before
  /// returning a pack.
  void assertBudget() {
    final bytes = serializedByteSize;
    if (bytes > budget.byteCap) {
      throw ContextPackOversizeException(
        actualBytes: bytes,
        capBytes: budget.byteCap,
        tier: budget.tier,
      );
    }
  }
}

class ContextPackOversizeException implements Exception {
  ContextPackOversizeException({
    required this.actualBytes,
    required this.capBytes,
    required this.tier,
  });

  final int actualBytes;
  final int capBytes;
  final BudgetTier tier;

  @override
  String toString() =>
      'ContextPackOversizeException(tier=${tier.wire}, '
      'actual=$actualBytes, cap=$capBytes)';
}

Map<String, Object?> _strKeyed(Map<Object?, Object?> raw) =>
    raw.map((k, v) => MapEntry(k.toString(), v));

const BaseContext _emptyBase = BaseContext(
  preferredCurrency: 'USD',
  riskPreference: RiskPreference.moderate,
  accounts: AccountSummary(totalCount: 0, byKind: <String, int>{}),
  cashflow: CashflowSummary(
    baseCurrency: 'USD',
    monthsCovered: 0,
    averageInflowMinor: '0',
    averageOutflowMinor: '0',
    trend: CashflowTrend.unknown,
  ),
);

// _emptyTask cannot be const because it transitively requires an
// IntentHint, which is itself const, but RouteContext + the empty
// lists inside TaskContext make the whole tree const-buildable.
const TaskContext _emptyTask = TaskContext(
  route: RouteContext(path: '/', area: 'unknown'),
  intent: IntentHint(capability: Capability.analyze, risk: RiskLevel.info),
);
