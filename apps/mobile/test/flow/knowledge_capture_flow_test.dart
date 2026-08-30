import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_route_paths.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  testWidgets('Task: Capture knowledge user saves an offline Note', (
    tester,
  ) async {
    final data = await FlowDataHarness.create();
    addTearDown(data.dispose);
    await data.enableDomains(const <DomainScope>[DomainScope.knowledge]);

    await bootApp(
      tester,
      liveData: data,
      initialLocation: KnowledgeRoutes.inbox,
    );
    final inbox = KnowledgeInboxPageObject(tester)..expectLanded();
    const body = 'Protect recovery before scheduling deep work.';
    const sourceUrl = 'https://example.com/recovery-notes';
    await inbox.captureNote(
      body,
      sourceUrl: sourceUrl,
      tags: 'recovery, planning',
    );
    inbox.expectNoteVisible(body);

    final repository = KnowledgeRepository(db: data.db, outbox: data.outbox);
    final notes = await repository.listNotes(ownerUserId: kLocalOnlyUserId);
    expect(notes, hasLength(1));
    expect(notes.single.sourceUrl, sourceUrl);
    expect(notes.single.tags, containsAll(<String>['recovery', 'planning']));
    await closeApp(tester);
  }, tags: 'flow');
}
