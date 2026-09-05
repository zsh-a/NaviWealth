import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_route_paths.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

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

  testWidgets(
    'decision capture uses a guarded page and preserves the note draft',
    (tester) async {
      final data = await FlowDataHarness.create();
      addTearDown(data.dispose);
      await data.enableDomains(const [DomainScope.knowledge]);
      await bootApp(
        tester,
        liveData: data,
        initialLocation: KnowledgeRoutes.inbox,
      );
      await tester.tap(find.bySemanticsLabel('New capture').first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('knowledge-capture-source-url')),
        findsNothing,
      );
      await tester.enterText(
        find.widgetWithText(FTextField, 'Content (Markdown)'),
        'Keep this note draft',
      );
      await tester.tap(find.text('Decisions'));
      await tester.pumpAndSettle();
      expect(find.byType(AppFormPageScaffold), findsOneWidget);
      await tester.enterText(
        find.byType(FTextField).first,
        'Should I proceed?',
      );
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(AppFormPageScaffold), findsNothing);
      expect(find.text('Keep this note draft'), findsOneWidget);
      await tester.tap(find.text('Decisions'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(FTextField, 'Question'),
        'Should I proceed?',
      );
      await tester.enterText(
        find.byKey(const ValueKey('knowledge-capture-option-label-0')),
        'Proceed',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final repository = KnowledgeRepository(db: data.db, outbox: data.outbox);
      final decisions = await repository.listDecisions(
        ownerUserId: kLocalOnlyUserId,
      );
      expect(decisions.single.question, 'Should I proceed?');
      expect(decisions.single.selectedLabel, 'Proceed');
      expect(find.byType(AppFormPageScaffold), findsNothing);
      expect(find.text('Keep this note draft'), findsOneWidget);
      await closeApp(tester);
    },
    tags: 'flow',
  );

  testWidgets('Task: Duplicate source warns without blocking capture', (
    tester,
  ) async {
    final data = await FlowDataHarness.create();
    addTearDown(data.dispose);
    await data.enableDomains(const <DomainScope>[DomainScope.knowledge]);
    final repository = KnowledgeRepository(db: data.db, outbox: data.outbox);
    final stamp = await data.stamper.stamp();
    await repository.upsertNote(
      KnowledgeNote(
        id: 'existing-source',
        title: 'Existing source',
        bodyMd: 'Previously captured.',
        sourceUrl: 'HTTPS://Example.com/article#first',
        createdAt: stamp.now,
        sync: SyncMeta(
          ownerUserId: stamp.ownerUserId,
          updatedAt: stamp.now,
          updatedByDevice: stamp.deviceId,
          hlc: stamp.hlc,
        ),
      ),
    );

    await bootApp(
      tester,
      liveData: data,
      initialLocation: KnowledgeRoutes.inbox,
    );
    final inbox = KnowledgeInboxPageObject(tester)..expectLanded();
    await inbox.captureNote(
      'A second perspective on the same source.',
      sourceUrl: 'example.com/article#second',
      duplicateSourceTitle: 'Existing source',
    );

    final notes = await repository.listNotes(ownerUserId: kLocalOnlyUserId);
    expect(notes, hasLength(2));
    expect(notes.map((note) => note.sourceUrl).toSet(), <String?>{
      'https://example.com/article',
    });
    await closeApp(tester);
  }, tags: 'flow');
}
