import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_route_paths.dart';

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
    await inbox.captureNote(body);
    inbox.expectNoteVisible(body);
    await closeApp(tester);
  }, tags: 'flow');
}
