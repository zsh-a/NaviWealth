/// KnowledgeOS domain models (`docs/domains/knowledgeos-domain.md` §3).
///
/// Plain Dart records over Drift rows — no freezed yet, since the
/// shape is still being shaken out by dogfood. Convert to freezed only
/// when copyWith / pattern matching starts paying off.
library;

import 'dart:convert';

import 'package:naviwealth/core/sync/sync_meta.dart';

/// Shared enum parser: returns the member whose [Enum.name] matches [s],
/// else [fallback]. Tolerates legacy / unknown wire values without
/// throwing. Every KnowledgeOS status enum routes its `parse` through
/// this so the lookup behaviour is identical across types; the
/// per-enum [fallback] differs only because each enum's natural default
/// differs (e.g. Experiment has no `active`).
T parseEnumByName<T extends Enum>(List<T> values, String s, T fallback) {
  for (final v in values) {
    if (v.name == s) return v;
  }
  return fallback;
}

/// Status of a [KnowledgePrinciple]. Principles are *not* falsifiable;
/// they can only be retired or paused when the user explicitly drops
/// the worldview primitive.
enum PrincipleStatus {
  active,
  paused,
  retired;

  String get wire => name;

  static PrincipleStatus parse(String s) =>
      parseEnumByName(values, s, PrincipleStatus.active);
}

/// Status of a [KnowledgeAssumption]. Assumptions *are* falsifiable —
/// when an experiment / event invalidates them they transition to
/// [weakened] (degraded confidence) or [falsified] (rejected).
enum AssumptionStatus {
  active,
  weakened,
  falsified,
  retired;

  String get wire => name;

  static AssumptionStatus parse(String s) =>
      parseEnumByName(values, s, AssumptionStatus.active);
}

/// 7-state lifecycle from §3. `superseded` is the key state — it carries
/// the `supersededByDecisionId` link so a chain of decisions reads as
/// cognitive evolution rather than overwrite.
enum DecisionStatus {
  draft,
  active,
  paused,
  expired,
  verified,
  falsified,
  superseded;

  String get wire => name;

  static DecisionStatus parse(String s) =>
      parseEnumByName(values, s, DecisionStatus.active);
}

enum ExperimentStatus {
  planned,
  running,
  done,
  abandoned;

  String get wire => name;

  static ExperimentStatus parse(String s) =>
      parseEnumByName(values, s, ExperimentStatus.planned);
}

/// Status of a [KnowledgeRoutine]. `paused` is a soft off-switch the
/// user can flip from the tile; `archived` is "this routine is done
/// forever" (kept for memory, no longer surfaced).
enum RoutineStatus {
  active,
  paused,
  archived;

  String get wire => name;

  static RoutineStatus parse(String s) =>
      parseEnumByName(values, s, RoutineStatus.active);
}

class KnowledgeNote {
  KnowledgeNote({
    required this.id,
    required this.title,
    required this.bodyMd,
    this.sourceUrl,
    required this.tags,
    this.projectTag,
    required this.createdAt,
    this.mergedIntoId,
    required this.sync,
  });

  final String id;
  final String title;
  final String bodyMd;
  final String? sourceUrl;
  final List<String> tags;
  final String? projectTag;
  final DateTime createdAt;

  /// Non-null only on a note that was merged into another (`§15.3`).
  /// Live notes are always null here. See [KnowledgeRepository.mergeNotes].
  final String? mergedIntoId;
  final SyncMeta sync;
}

class KnowledgePrinciple {
  KnowledgePrinciple({
    required this.id,
    required this.statement,
    required this.rationaleMd,
    required this.scope,
    required this.status,
    required this.declaredAt,
    this.mergedIntoId,
    required this.sync,
  });

  final String id;
  final String statement;
  final String rationaleMd;
  final String scope;
  final PrincipleStatus status;
  final DateTime declaredAt;

  /// Non-null only on a principle merged into another (`§15.3`).
  final String? mergedIntoId;
  final SyncMeta sync;
}

class KnowledgeAssumption {
  KnowledgeAssumption({
    required this.id,
    required this.statement,
    required this.confidence,
    required this.scope,
    required this.evidenceIds,
    required this.status,
    required this.declaredAt,
    this.lastVerifiedAt,
    this.mergedIntoId,
    required this.sync,
  });

  final String id;
  final String statement;
  final double confidence;
  final String scope;
  final List<String> evidenceIds;
  final AssumptionStatus status;
  final DateTime declaredAt;
  final DateTime? lastVerifiedAt;

  /// Non-null only on an assumption merged into another (`§15.3`).
  final String? mergedIntoId;
  final SyncMeta sync;

  int daysSinceVerify(DateTime now) {
    final ref = lastVerifiedAt ?? declaredAt;
    return now.toUtc().difference(ref.toUtc()).inDays;
  }
}

/// One option considered when making a [KnowledgeDecision]. Held inline
/// in `options_json` rather than its own table — they don't outlive the
/// decision they belong to.
class DecisionOption {
  DecisionOption({required this.label, this.rationale});
  final String label;
  final String? rationale;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    if (rationale != null) 'rationale': rationale,
  };

  static DecisionOption fromJson(Map<String, Object?> j) => DecisionOption(
    label: (j['label'] as String?) ?? '',
    rationale: j['rationale'] as String?,
  );

  static List<DecisionOption> decode(String jsonStr) {
    if (jsonStr.isEmpty) return const <DecisionOption>[];
    final v = jsonDecode(jsonStr);
    if (v is! List) return const <DecisionOption>[];
    return v
        .whereType<Map<String, Object?>>()
        .map(DecisionOption.fromJson)
        .toList(growable: false);
  }

  static String encode(List<DecisionOption> opts) =>
      jsonEncode(opts.map((o) => o.toJson()).toList(growable: false));
}

class KnowledgeDecision {
  KnowledgeDecision({
    required this.id,
    required this.question,
    required this.options,
    required this.selectedLabel,
    required this.rationaleMd,
    required this.principleIds,
    required this.assumptionIds,
    this.expectedOutcome,
    this.reviewDate,
    this.actualOutcomeMd,
    required this.status,
    this.supersededByDecisionId,
    this.contextSnapshot,
    required this.decidedAt,
    this.mergedIntoId,
    required this.sync,
  });

  final String id;
  final String question;
  final List<DecisionOption> options;
  final String selectedLabel;
  final String rationaleMd;
  final List<String> principleIds;
  final List<String> assumptionIds;
  final String? expectedOutcome;
  final DateTime? reviewDate;
  final String? actualOutcomeMd;
  final DecisionStatus status;
  final String? supersededByDecisionId;
  final Map<String, Object?>? contextSnapshot;
  final DateTime decidedAt;

  /// Non-null only on a decision merged into another (`§15.3`). Distinct
  /// from [supersededByDecisionId] — merge = "same decision, deduped",
  /// supersede = "a later decision replaced this one".
  final String? mergedIntoId;
  final SyncMeta sync;

  int? daysOverdue(DateTime now) {
    if (reviewDate == null) return null;
    return now.toUtc().difference(reviewDate!.toUtc()).inDays;
  }
}

class KnowledgeConcept {
  KnowledgeConcept({
    required this.id,
    required this.name,
    required this.aliases,
    required this.summaryMd,
    required this.relatedConceptIds,
    required this.createdAt,
    this.mergedIntoId,
    required this.sync,
  });

  final String id;
  final String name;
  final List<String> aliases;
  final String summaryMd;
  final List<String> relatedConceptIds;
  final DateTime createdAt;

  /// Non-null only on a concept merged into another (`§15.3`).
  final String? mergedIntoId;
  final SyncMeta sync;
}

class KnowledgeExperiment {
  KnowledgeExperiment({
    required this.id,
    required this.hypothesis,
    required this.methodMd,
    required this.metrics,
    required this.status,
    this.resultMd,
    this.conclusionMd,
    this.targetAssumptionId,
    required this.startedAt,
    this.endedAt,
    this.mergedIntoId,
    required this.sync,
  });

  final String id;
  final String hypothesis;
  final String methodMd;
  final List<String> metrics;
  final ExperimentStatus status;
  final String? resultMd;
  final String? conclusionMd;
  final String? targetAssumptionId;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// Non-null only on an experiment merged into another (`§15.3`).
  final String? mergedIntoId;
  final SyncMeta sync;
}

/// Recurring user-defined reminder. `nextDueAt` is the single source of
/// truth for "when does this surface again" — bumped to `now + intervalDays`
/// on `markDone`. RoutineDueAgent scans `nextDueAt <= now + 7d` daily and
/// emits a memory + local notification.
class KnowledgeRoutine {
  KnowledgeRoutine({
    required this.id,
    required this.statement,
    required this.intervalDays,
    required this.nextDueAt,
    this.lastDoneAt,
    required this.scope,
    required this.status,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final String statement;
  final int intervalDays;
  final DateTime? lastDoneAt;
  final DateTime nextDueAt;
  final String scope;
  final RoutineStatus status;
  final DateTime createdAt;
  final SyncMeta sync;

  int daysUntilDue(DateTime now) =>
      nextDueAt.toUtc().difference(now.toUtc()).inDays;

  bool isDue(DateTime now) => !nextDueAt.toUtc().isAfter(now.toUtc());
}

/// JSON helpers — every list/map column in §9 is stored as JSON text.
List<String> decodeStringList(String s) {
  if (s.isEmpty) return const <String>[];
  final v = jsonDecode(s);
  if (v is! List) return const <String>[];
  return v.whereType<String>().toList(growable: false);
}

String encodeStringList(List<String> xs) => jsonEncode(xs);

Map<String, Object?>? decodeNullableJsonMap(String? s) {
  if (s == null || s.isEmpty) return null;
  final v = jsonDecode(s);
  if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
  return null;
}

String? encodeNullableJsonMap(Map<String, Object?>? m) =>
    m == null ? null : jsonEncode(m);
