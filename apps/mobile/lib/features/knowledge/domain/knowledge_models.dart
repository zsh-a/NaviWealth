/// Canonical KnowledgeOS models: Notes, Decisions, and Relations.
library;

import 'dart:convert';

import 'package:naviwealth/core/sync/sync_meta.dart';

enum DecisionStatus {
  draft,
  active,
  paused,
  expired,
  verified,
  falsified,
  superseded;

  String get wire => name;

  static DecisionStatus parse(String value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return DecisionStatus.active;
  }
}

class KnowledgeNote {
  KnowledgeNote({
    required this.id,
    required this.title,
    required this.bodyMd,
    this.sourceUrl,
    this.tags = const <String>[],
    required this.createdAt,
    this.mergedIntoId,
    required this.sync,
  });

  final String id;
  final String title;
  final String bodyMd;
  final String? sourceUrl;
  final List<String> tags;
  final DateTime createdAt;
  final String? mergedIntoId;
  final SyncMeta sync;
}

class DecisionOption {
  DecisionOption({required this.label, this.rationale});

  final String label;
  final String? rationale;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    if (rationale != null) 'rationale': rationale,
  };

  static DecisionOption fromJson(Map<String, Object?> json) => DecisionOption(
    label: json['label'] as String? ?? '',
    rationale: json['rationale'] as String?,
  );

  static List<DecisionOption> decode(String value) {
    if (value.isEmpty) return const <DecisionOption>[];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const <DecisionOption>[];
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => DecisionOption.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  static String encode(List<DecisionOption> options) => jsonEncode(
    options.map((option) => option.toJson()).toList(growable: false),
  );
}

class DecisionRevisitCondition {
  const DecisionRevisitCondition({
    required this.statement,
    this.sourceReferences = const <String>[],
  });

  final String statement;
  final List<String> sourceReferences;

  Map<String, Object?> toJson() => <String, Object?>{
    'statement': statement,
    'source_references': sourceReferences,
  };

  static DecisionRevisitCondition fromJson(Map<String, Object?> json) {
    final references = json['source_references'];
    return DecisionRevisitCondition(
      statement: json['statement'] as String? ?? '',
      sourceReferences: references is List
          ? references.whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }

  static List<DecisionRevisitCondition> decode(String value) {
    if (value.isEmpty) return const <DecisionRevisitCondition>[];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const <DecisionRevisitCondition>[];
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map(
          (item) => DecisionRevisitCondition.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where((condition) => condition.statement.trim().isNotEmpty)
        .toList(growable: false);
  }

  static String encode(List<DecisionRevisitCondition> conditions) => jsonEncode(
    conditions.map((condition) => condition.toJson()).toList(growable: false),
  );
}

class KnowledgeDecision {
  KnowledgeDecision({
    required this.id,
    required this.question,
    required this.options,
    required this.selectedLabel,
    required this.rationaleMd,
    this.expectedOutcome,
    this.reviewDate,
    this.revisitConditions = const <DecisionRevisitCondition>[],
    this.actualOutcomeMd,
    required this.status,
    this.supersededByDecisionId,
    required this.decidedAt,
    this.mergedIntoId,
    required this.sync,
  });

  final String id;
  final String question;
  final List<DecisionOption> options;
  final String selectedLabel;
  final String rationaleMd;
  final String? expectedOutcome;
  final DateTime? reviewDate;
  final List<DecisionRevisitCondition> revisitConditions;
  final String? actualOutcomeMd;
  final DecisionStatus status;
  final String? supersededByDecisionId;
  final DateTime decidedAt;
  final String? mergedIntoId;
  final SyncMeta sync;

  int? daysOverdue(DateTime now) {
    final date = reviewDate;
    if (date == null) return null;
    return now.toUtc().difference(date.toUtc()).inDays;
  }
}

enum KnowledgeRelationType {
  relatedTo('related_to'),
  informs('informs');

  const KnowledgeRelationType(this.wire);

  final String wire;

  static KnowledgeRelationType parse(String value) => switch (value) {
    'informs' => KnowledgeRelationType.informs,
    _ => KnowledgeRelationType.relatedTo,
  };
}

class KnowledgeRelation {
  const KnowledgeRelation({
    required this.id,
    required this.fromKind,
    required this.fromId,
    required this.relation,
    required this.toKind,
    required this.toId,
    required this.createdAt,
    required this.sync,
  });

  final String id;
  final String fromKind;
  final String fromId;
  final KnowledgeRelationType relation;
  final String toKind;
  final String toId;
  final DateTime createdAt;
  final SyncMeta sync;
}

List<String> decodeStringList(String value) {
  if (value.isEmpty) return const <String>[];
  final decoded = jsonDecode(value);
  if (decoded is! List) return const <String>[];
  return decoded.whereType<String>().toList(growable: false);
}

String encodeStringList(List<String> values) => jsonEncode(values);
