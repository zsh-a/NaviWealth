import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_bridge.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_sync_controller.dart';
import 'package:naviwealth/features/health/data/garmin/garmin_sync_issue.dart';

void main() {
  test('parses structured Garmin sync issues', () {
    final issues = parseGarminSyncIssues([
      '{"source":"healthos.garmin","code":"auth_expired","severity":"error","endpoint":"sleep","message":"Garmin session expired","detail":"401 Unauthorized","retryable":false,"action":"reconnect"}',
    ]);

    expect(issues, hasLength(1));
    expect(issues.first.code, 'auth_expired');
    expect(issues.first.endpoint, 'sleep');
    expect(issues.first.requiresReconnect, isTrue);
    expect(issues.fatal, hasLength(1));
  });

  test('classifies legacy optional 404 endpoint strings as warnings', () {
    final issue = GarminSyncIssue.fromLegacyMessage(
      'activities fetch failed: Garmin API error: 404 Not Found',
    );

    expect(issue.code, 'endpoint_unavailable');
    expect(issue.endpoint, 'activities');
    expect(issue.isFatal, isFalse);
  });

  test('rate limiting takes priority over optional endpoint warnings', () {
    final unavailable = GarminSyncIssue.fromLegacyMessage(
      'activities fetch failed: Garmin API error: 404 Not Found',
    );
    const limited = GarminSyncIssue(
      code: 'rate_limited',
      severity: GarminSyncIssueSeverity.warning,
      message: 'Garmin temporarily limited requests',
      action: GarminSyncIssueAction.retryLater,
    );
    expect([unavailable, limited].primary?.code, 'rate_limited');
    expect(
      [unavailable, limited, GarminSyncIssue.noSnapshot()].primary?.code,
      'snapshot_missing',
    );
  });

  test(
    'rate limiting during startup preserves its cooldown classification',
    () {
      final issue = GarminSyncIssue.fromLegacyMessage(
        'Garmin profile fetch failed: HTTP 429 Too Many Requests',
      );
      expect(issue.code, 'rate_limited');
      expect(issue.isFatal, isTrue);
      expect(issue.action, GarminSyncIssueAction.retryLater);
    },
  );

  test('maps restored expired auth failure to reconnect error', () {
    final issue = garminRestoreAuthIssue(
      GarminAuthState.fromJson({
        'Error': {'message': 'DI token expired'},
      }),
    );

    expect(issue.code, 'auth_expired');
    expect(issue.requiresReconnect, isTrue);
    expect(issue.detail, contains('DI token expired'));
  });

  test('maps unauthenticated restored auth state to reconnect error', () {
    final issue = garminRestoreAuthIssue(GarminAuthState.unauthenticated);

    expect(issue.code, 'auth_expired');
    expect(issue.requiresReconnect, isTrue);
  });
}
