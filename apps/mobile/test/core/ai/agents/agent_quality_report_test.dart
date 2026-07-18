import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_artifact_store.dart';
import 'package:naviwealth/core/ai/agents/agent_quality_report.dart';

import '../../persistence/test_database.dart';

void main() {
  test(
    'aggregates lifecycle and visibility metrics without private text',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final now = DateTime.utc(2026, 7, 18);
      final since = now.subtract(const Duration(days: 30));

      Future<void> insertRun(String id, String status, DateTime startedAt) {
        return db.customStatement(
          '''
        INSERT INTO agent_runs (
          id, owner_user_id, agent_id, agent_name, status, trigger,
          started_at, finished_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
          <Object?>[
            id,
            'user-1',
            'agent-1',
            'Private agent name',
            status,
            'schedule',
            startedAt.millisecondsSinceEpoch,
            startedAt.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
          ],
        );
      }

      await insertRun('ready', 'ready', now.subtract(const Duration(days: 1)));
      await insertRun(
        'no-finding',
        'no_finding',
        now.subtract(const Duration(days: 2)),
      );
      await insertRun(
        'failed',
        'failed',
        now.subtract(const Duration(days: 3)),
      );
      await insertRun(
        'old',
        'failed',
        since.subtract(const Duration(seconds: 1)),
      );

      final store = SqliteAgentArtifactStore(db: db);
      AgentArtifact artifact({
        required String id,
        required DateTime createdAt,
        required List<AgentEvidenceRef> evidence,
      }) => AgentArtifact(
        id: id,
        ownerUserId: 'user-1',
        agentId: 'agent-1',
        domain: 'finance',
        kind: AgentArtifactKind.review,
        severity: AgentArtifactSeverity.info,
        title: 'Private title',
        summary: 'Private summary',
        evidence: evidence,
        createdAt: createdAt,
      );

      await store.save(
        artifact(
          id: 'anchored',
          createdAt: now.subtract(const Duration(days: 1)),
          evidence: const <AgentEvidenceRef>[
            AgentEvidenceRef(
              type: 'finance_row',
              id: 'private-id',
              route: '/wealth',
            ),
          ],
        ),
      );
      await store.save(
        artifact(
          id: 'unanchored',
          createdAt: now.subtract(const Duration(days: 2)),
          evidence: const <AgentEvidenceRef>[
            AgentEvidenceRef(type: 'finance_row', id: 'private-id-2'),
          ],
        ),
      );
      await store.dismiss(
        ownerUserId: 'user-1',
        id: 'unanchored',
        dismissedAt: now,
      );

      final report = await SqliteAgentQualityReportReader(
        db,
      ).read(ownerUserId: 'user-1', since: since, now: now);

      expect(report.completedRuns, 3);
      expect(report.highSignalRate, closeTo(1 / 3, 0.0001));
      expect(report.noFindingRate, closeTo(1 / 3, 0.0001));
      expect(report.failureRate, closeTo(1 / 3, 0.0001));
      expect(report.artifactCount, 2);
      expect(report.dismissedOrSnoozedRate, 0.5);
      expect(report.evidenceAnchorCoverageRate, 0.5);

      final encoded = report.toJson().toString();
      expect(encoded, isNot(contains('Private')));
      expect(encoded, isNot(contains('private-id')));
    },
  );

  test('empty report exposes zero rates', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 7, 18);

    final report = await SqliteAgentQualityReportReader(db).read(
      ownerUserId: 'user-1',
      since: now.subtract(const Duration(days: 30)),
      now: now,
    );

    expect(report.completedRuns, 0);
    expect(report.highSignalRate, 0);
    expect(report.evidenceAnchorCoverageRate, 0);
  });
}
