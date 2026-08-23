/// Background-safe attention inspection over a precomputed primitive snapshot.
///
/// This module has no AI runtime, tool, proposal, repository, or Drift
/// dependency. A background isolate can only read the bounded snapshot and
/// persist a pending attention decision in SharedPreferences.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../agents/agent_artifact.dart';
import 'attention.dart';

const String kBackgroundSafeLifeSnapshotKey =
    'lifeos.attention.precomputed_snapshot';
const String kPendingBackgroundAttentionKey =
    'lifeos.attention.pending_decision';

class BackgroundSafeLifeSnapshot {
  const BackgroundSafeLifeSnapshot({
    required this.ownerUserId,
    required this.fingerprint,
    required this.computedAt,
    required this.notificationsAllowed,
    required this.recentInterruptCount,
    required this.candidates,
  });

  final String ownerUserId;
  final String fingerprint;
  final DateTime computedAt;
  final bool notificationsAllowed;
  final int recentInterruptCount;
  final List<AttentionCandidate> candidates;

  Map<String, Object?> toJson() => <String, Object?>{
    'owner_user_id': ownerUserId,
    'fingerprint': fingerprint,
    'computed_at': computedAt.toUtc().toIso8601String(),
    'notifications_allowed': notificationsAllowed,
    'recent_interrupt_count': recentInterruptCount,
    'candidates': [for (final candidate in candidates) candidate.toJson()],
  };

  factory BackgroundSafeLifeSnapshot.fromJson(Map<String, Object?> json) {
    return BackgroundSafeLifeSnapshot(
      ownerUserId: json['owner_user_id']! as String,
      fingerprint: json['fingerprint']! as String,
      computedAt: DateTime.parse(json['computed_at']! as String).toUtc(),
      notificationsAllowed: json['notifications_allowed']! as bool,
      recentInterruptCount: json['recent_interrupt_count']! as int,
      candidates: <AttentionCandidate>[
        for (final value in json['candidates']! as List)
          AttentionCandidate.fromJson((value as Map).cast<String, Object?>()),
      ],
    );
  }
}

class BackgroundSafeAttentionEvaluator {
  const BackgroundSafeAttentionEvaluator({
    this.maxSnapshotAge = const Duration(hours: 24),
    this.arbiter = const AttentionArbiter(),
  });

  final Duration maxSnapshotAge;
  final AttentionArbiter arbiter;

  AttentionDecision? inspect(
    BackgroundSafeLifeSnapshot snapshot, {
    required DateTime now,
  }) {
    final at = now.toUtc();
    if (at.difference(snapshot.computedAt.toUtc()) > maxSnapshotAge) {
      return null;
    }
    final candidates = snapshot.candidates.toList()
      ..sort((a, b) {
        final severity = _severityRank(b).compareTo(_severityRank(a));
        return severity != 0 ? severity : b.confidence.compareTo(a.confidence);
      });
    for (final candidate in candidates) {
      final decision = arbiter.decide(
        ownerUserId: snapshot.ownerUserId,
        candidate: candidate,
        context: AttentionPolicyContext(
          novel: true,
          suppressed: false,
          notificationsAllowed: snapshot.notificationsAllowed,
          recentInterruptCount: snapshot.recentInterruptCount,
        ),
        decidedAt: at,
      );
      if (decision.level == AttentionLevel.interrupt) return decision;
    }
    return null;
  }
}

int _severityRank(AttentionCandidate candidate) => switch (candidate.severity) {
  AgentArtifactSeverity.warning => 3,
  AgentArtifactSeverity.attention => 2,
  AgentArtifactSeverity.info => 1,
};

class SharedPreferencesBackgroundSafeAttentionStore {
  const SharedPreferencesBackgroundSafeAttentionStore(this._preferences);

  final SharedPreferences _preferences;

  Future<void> saveSnapshot(BackgroundSafeLifeSnapshot snapshot) {
    return _preferences.setString(
      kBackgroundSafeLifeSnapshotKey,
      jsonEncode(snapshot.toJson()),
    );
  }

  BackgroundSafeLifeSnapshot? readSnapshot() {
    final encoded = _preferences.getString(kBackgroundSafeLifeSnapshotKey);
    if (encoded == null) return null;
    try {
      return BackgroundSafeLifeSnapshot.fromJson(
        (jsonDecode(encoded) as Map).cast<String, Object?>(),
      );
    } on Object {
      return null;
    }
  }

  Future<void> savePending(AttentionDecision decision) {
    return _preferences.setString(
      kPendingBackgroundAttentionKey,
      jsonEncode(decision.toJson()),
    );
  }

  String? readPendingJson() {
    return _preferences.getString(kPendingBackgroundAttentionKey);
  }

  Future<void> clearPending() {
    return _preferences.remove(kPendingBackgroundAttentionKey);
  }
}
