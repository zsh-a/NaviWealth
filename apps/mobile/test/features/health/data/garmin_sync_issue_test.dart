import 'package:flutter_test/flutter_test.dart';
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
}
