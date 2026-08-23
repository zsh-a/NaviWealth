import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/attention/attention.dart';
import 'package:naviwealth/core/ai/attention/background_safe_attention.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.utc(2026, 8, 23, 8);

BackgroundSafeLifeSnapshot _snapshot({DateTime? computedAt}) {
  return BackgroundSafeLifeSnapshot(
    ownerUserId: 'owner',
    fingerprint: 'context-v1',
    computedAt: computedAt ?? _now,
    notificationsAllowed: true,
    recentInterruptCount: 0,
    candidates: <AttentionCandidate>[
      AttentionCandidate(
        id: 'recovery-alert',
        agentId: 'daily_navigator',
        findingFingerprint: 'recovery-v1',
        severity: AgentArtifactSeverity.warning,
        confidence: 0.9,
        actionable: true,
        fresh: true,
        evidenceComplete: true,
        observedAt: _now,
      ),
    ],
  );
}

void main() {
  test(
    'inspects only a precomputed snapshot and persists pending attention',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesBackgroundSafeAttentionStore(preferences);
      await store.saveSnapshot(_snapshot());

      final loaded = store.readSnapshot();
      final decision = const BackgroundSafeAttentionEvaluator().inspect(
        loaded!,
        now: _now.add(const Duration(hours: 1)),
      );
      await store.savePending(decision!);

      expect(decision.level, AttentionLevel.interrupt);
      expect(store.readPendingJson(), contains('recovery-alert'));
      expect(preferences.getKeys(), <String>{
        kBackgroundSafeLifeSnapshotKey,
        kPendingBackgroundAttentionKey,
      });
    },
  );

  test('stale precomputed snapshot fails closed', () {
    final decision = const BackgroundSafeAttentionEvaluator().inspect(
      _snapshot(computedAt: _now.subtract(const Duration(days: 2))),
      now: _now,
    );

    expect(decision, isNull);
  });
}
