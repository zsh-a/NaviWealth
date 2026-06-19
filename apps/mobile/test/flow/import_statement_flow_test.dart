// Flow / Task test: "Import CSV / statement" — Task #4 in
// docs/testing-strategy.md.
//
// This boots the real app shell, discovers the ingest review queue from
// Activity, pastes a small CSV statement, and proves the pipeline stages rows
// as explicit review drafts instead of silently committing them.

import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Import CSV / statement', () {
    late FlowDataHarness data;

    setUp(() async {
      data = await FlowDataHarness.create();
    });

    tearDown(() async {
      await data.dispose();
    });

    testWidgets('user pastes a statement and gets reviewable drafts', (
      tester,
    ) async {
      await bootApp(tester, liveData: data);

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Activity');

      final activity = ActivityPageObject(tester);
      await activity.openIngestQueue();

      final ingest = IngestReviewPageObject(tester);
      ingest.expectLandedEmpty();
      await ingest.pasteStatement(
        'date,description,amount,currency\n'
        '2026-05-10,STARBUCKS 04291,-38.00,CNY\n'
        '2026-05-12,Metro Groceries,-64.50,CNY\n',
      );

      ingest.expectDraftVisible('STARBUCKS 04291');
      ingest.expectDraftVisible('Metro Groceries');
      ingest.expectConfirmAllCount(2);
      await closeApp(tester);
    }, tags: 'flow');
  });
}
