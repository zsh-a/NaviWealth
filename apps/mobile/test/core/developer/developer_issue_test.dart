import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/config/app_version.dart';
import 'package:naviwealth/core/developer/developer_issue.dart';
import 'package:uuid/uuid.dart';

import '../persistence/test_database.dart';

void main() {
  test(
    'captures bounded diagnostics and exports no account identity',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final store = SqliteDeveloperIssueStore(db);
      final service = DeveloperIssueCaptureService(
        store: store,
        uuid: const Uuid(),
      );
      final issue = await service.capture(
        ownerUserId: 'private-user-id',
        description: '  FIRE hierarchy hides the next action.  ',
        context: const DeveloperIssueContext(
          route: '/finance/fire',
          domain: 'finance',
        ),
        version: const AppVersionInfo(
          version: '2.0.0',
          buildNumber: '42',
          commitSha: 'abc123',
        ),
        recentTraces: <AiTrace>[_traceWithSixToolErrors()],
        screenshotPath: '/private/cache/report.png',
        at: DateTime.utc(2026, 8, 23, 9),
      );

      expect(issue.description, 'FIRE hierarchy hides the next action.');
      expect(issue.traceId, 'trace-latest');
      expect(issue.toolErrors, hasLength(kDeveloperIssueToolErrorLimit));
      expect(issue.toolErrors.first.errorCode, 'tool_error_0');

      final stored = await store.list(ownerUserId: 'private-user-id');
      expect(stored, hasLength(1));
      expect(stored.single.route, '/finance/fire');
      expect(stored.single.screenshotPath, '/private/cache/report.png');

      final export = issue.toExportText();
      final decoded = jsonDecode(export) as Map<String, Object?>;
      expect(export, isNot(contains('private-user-id')));
      expect(export, isNot(contains('/private/cache/report.png')));
      expect(export, isNot(contains('provider secret response')));
      expect(decoded['has_screenshot'], isTrue);
      expect(decoded['schema'], 'naviwealth.developer_issue.v1');

      final exportedAt = DateTime.utc(2026, 8, 23, 10);
      await store.markExported(
        ownerUserId: issue.ownerUserId,
        issueId: issue.id,
        at: exportedAt,
      );
      final exported = await store.list(ownerUserId: issue.ownerUserId);
      expect(exported.single.exportedAt, exportedAt);
    },
  );
}

AiTrace _traceWithSixToolErrors() => AiTrace(
  requestId: 'trace-latest',
  startedAtIso: '2026-08-23T08:00:00.000Z',
  intent: const IntentHint(
    capability: Capability.analyze,
    risk: RiskLevel.info,
  ),
  backend: Backend.device,
  budgetTier: BudgetTier.standard,
  routingReason: kDeterministicAgentRoutingReason,
  totalDurationMs: 10,
  spans: <AiSpan>[
    for (var index = 0; index < 6; index++)
      AiSpan(
        id: 'tool-$index',
        kind: AiSpanKind.tool,
        name: 'tool:sample_$index',
        startOffsetMs: index,
        durationMs: 1,
        status: AiSpanStatus.error,
        errorCode: 'tool_error_$index',
        errorMessage: 'provider secret response',
      ),
  ],
);
