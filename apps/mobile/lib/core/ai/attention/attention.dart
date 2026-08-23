/// Global attention policy for personal-intelligence candidates.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../agents/agent_artifact.dart';

enum AttentionLevel { silent, surface, interrupt }

@immutable
class AttentionCandidate {
  const AttentionCandidate({
    required this.id,
    required this.agentId,
    required this.findingFingerprint,
    required this.severity,
    required this.confidence,
    required this.actionable,
    required this.fresh,
    required this.evidenceComplete,
    required this.observedAt,
  });

  final String id;
  final String agentId;
  final String findingFingerprint;
  final AgentArtifactSeverity severity;
  final double confidence;
  final bool actionable;
  final bool fresh;
  final bool evidenceComplete;
  final DateTime observedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'agent_id': agentId,
    'finding_fingerprint': findingFingerprint,
    'severity': severity.wire,
    'confidence': confidence,
    'actionable': actionable,
    'fresh': fresh,
    'evidence_complete': evidenceComplete,
    'observed_at': observedAt.toUtc().toIso8601String(),
  };

  factory AttentionCandidate.fromJson(Map<String, Object?> json) {
    return AttentionCandidate(
      id: json['id']! as String,
      agentId: json['agent_id']! as String,
      findingFingerprint: json['finding_fingerprint']! as String,
      severity: agentArtifactSeverityFromWire(json['severity']! as String),
      confidence: (json['confidence']! as num).toDouble(),
      actionable: json['actionable']! as bool,
      fresh: json['fresh']! as bool,
      evidenceComplete: json['evidence_complete']! as bool,
      observedAt: DateTime.parse(json['observed_at']! as String).toUtc(),
    );
  }
}

@immutable
class AttentionPolicyContext {
  const AttentionPolicyContext({
    required this.novel,
    required this.suppressed,
    required this.notificationsAllowed,
    required this.recentInterruptCount,
    this.interruptBudget = 3,
  });

  final bool novel;
  final bool suppressed;
  final bool notificationsAllowed;
  final int recentInterruptCount;
  final int interruptBudget;
}

@immutable
class AttentionDecision {
  AttentionDecision({
    required this.ownerUserId,
    required this.candidate,
    required this.level,
    required Iterable<String> reasons,
    required this.createdAt,
  }) : reasons = List<String>.unmodifiable(reasons) {
    id = _decisionId(ownerUserId, candidate, level);
  }

  late final String id;
  final String ownerUserId;
  final AttentionCandidate candidate;
  final AttentionLevel level;
  final List<String> reasons;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'owner_user_id': ownerUserId,
    'candidate': candidate.toJson(),
    'level': level.name,
    'reasons': reasons,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory AttentionDecision.fromJson(Map<String, Object?> json) {
    return AttentionDecision(
      ownerUserId: json['owner_user_id']! as String,
      candidate: AttentionCandidate.fromJson(
        (json['candidate']! as Map).cast<String, Object?>(),
      ),
      level: AttentionLevel.values.byName(json['level']! as String),
      reasons: (json['reasons']! as List).whereType<String>(),
      createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
    );
  }
}

class AttentionArbiter {
  const AttentionArbiter();

  AttentionDecision decide({
    required String ownerUserId,
    required AttentionCandidate candidate,
    required AttentionPolicyContext context,
    required DateTime decidedAt,
  }) {
    if (context.suppressed) {
      return _decision(
        ownerUserId,
        candidate,
        AttentionLevel.silent,
        decidedAt,
        'finding_suppressed',
      );
    }
    if (!context.novel) {
      return _decision(
        ownerUserId,
        candidate,
        AttentionLevel.silent,
        decidedAt,
        'unchanged_finding',
      );
    }
    if (!candidate.fresh) {
      return _decision(
        ownerUserId,
        candidate,
        AttentionLevel.silent,
        decidedAt,
        'stale_input',
      );
    }
    if (!candidate.evidenceComplete) {
      return _decision(
        ownerUserId,
        candidate,
        AttentionLevel.silent,
        decidedAt,
        'incomplete_evidence',
      );
    }
    if (candidate.confidence < 0.65) {
      return _decision(
        ownerUserId,
        candidate,
        AttentionLevel.silent,
        decidedAt,
        'low_confidence',
      );
    }
    final canInterrupt =
        candidate.severity == AgentArtifactSeverity.warning &&
        candidate.actionable &&
        candidate.confidence >= 0.85 &&
        context.notificationsAllowed &&
        context.recentInterruptCount < context.interruptBudget;
    if (canInterrupt) {
      return AttentionDecision(
        ownerUserId: ownerUserId,
        candidate: candidate,
        level: AttentionLevel.interrupt,
        reasons: const <String>['urgent_actionable_within_budget'],
        createdAt: decidedAt,
      );
    }
    return AttentionDecision(
      ownerUserId: ownerUserId,
      candidate: candidate,
      level: AttentionLevel.surface,
      reasons: <String>[
        if (!candidate.actionable) 'not_actionable',
        if (!context.notificationsAllowed) 'notifications_disabled',
        if (context.recentInterruptCount >= context.interruptBudget)
          'interrupt_budget_exhausted',
        if (candidate.severity != AgentArtifactSeverity.warning)
          'non_interrupting_severity',
      ],
      createdAt: decidedAt,
    );
  }

  AttentionDecision _decision(
    String ownerUserId,
    AttentionCandidate candidate,
    AttentionLevel level,
    DateTime at,
    String reason,
  ) => AttentionDecision(
    ownerUserId: ownerUserId,
    candidate: candidate,
    level: level,
    reasons: <String>[reason],
    createdAt: at,
  );
}

String _decisionId(
  String ownerUserId,
  AttentionCandidate candidate,
  AttentionLevel level,
) {
  final material = jsonEncode(<String, Object?>{
    'owner': ownerUserId,
    'candidate': candidate.id,
    'fingerprint': candidate.findingFingerprint,
    'level': level.name,
  });
  return 'attention:${sha256.convert(utf8.encode(material))}';
}
