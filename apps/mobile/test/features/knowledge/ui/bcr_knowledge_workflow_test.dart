import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/forms/local_form_draft.dart';
import 'package:naviwealth/core/lifeos/action_dispatcher.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/bcr_knowledge_providers.dart';
import 'package:naviwealth/features/knowledge/data/bcr_knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/domain/bcr_knowledge_source.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/bcr_knowledge_library_page.dart';
import 'package:naviwealth/features/knowledge/ui/bcr_knowledge_reader.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_decision_detail_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';
import '../../../support/test_app_theme.dart';
import '../../finance/data/repositories/_stub_stamper.dart';
import '../bcr_sync_test_fixture.dart';
import '../bcr_test_fixture.dart';

void main() {
  testWidgets(
    'connect without a page URL, read and cite a snapshot without changing past evidence',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = makeTestDatabase();
      addTearDown(db.close);
      final outbox = InMemoryOutboxStore();
      final sources = BcrKnowledgeRepository(db);
      final decisions = KnowledgeRepository(db: db, outbox: outbox);
      final stamper = makeStubStamper(userId: 'owner');
      final client = FakeBcrGithubClient();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          currentUserIdProvider.overrideWithValue(() async => 'owner'),
          outboxStoreProvider.overrideWith((ref) async => outbox),
          mutationStamperProvider.overrideWith((ref) async => stamper),
          localFormDraftStoreProvider.overrideWithValue(null),
          secureKeyStoreProvider.overrideWithValue(InMemoryKeyStore()),
          bcrGithubClientProvider.overrideWithValue(client),
          lifeSourceActionReaderProvider.overrideWith(
            (ref) =>
                (_) async => null,
          ),
          lifeActionRouteBuilderProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);
      Widget wrap(Widget home) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: buildTestAppTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: home,
        ),
      );

      await tester.pumpWidget(wrap(const BcrKnowledgeLibraryPage()));
      await _settle(tester);
      await tester.tap(find.text('Connect a source'));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('bcr-source-name')),
        'Research',
      );
      expect(find.byKey(const Key('bcr-source-url')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('bcr-source-repository')),
        'account/research',
      );
      await tester.enterText(
        find.byKey(const Key('bcr-source-token')),
        'test-token',
      );
      expect(await sources.listSources('owner'), isEmpty);
      await tester.tap(find.byKey(const Key('bcr-connect-submit')));
      await _settle(tester);
      final snapshot = (await sources.listSources('owner')).single;
      expect(snapshot.libraryUrl, isNull);
      expect(find.text('Asset allocation'), findsOneWidget);
      expect(await db.select(db.knowledgeNotes).get(), isEmpty);
      expect(outbox.items, isEmpty);

      final stamp = await stamper.stamp();
      await decisions.upsertDecision(
        KnowledgeDecision(
          id: 'decision',
          question: 'Raise equity allocation?',
          options: [DecisionOption(label: 'Keep')],
          selectedLabel: 'Keep',
          rationaleMd: 'Keep a buffer.',
          status: DecisionStatus.active,
          decidedAt: stamp.now,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.pumpWidget(
        wrap(const KnowledgeDecisionDetailPage(decisionId: 'decision')),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const Key('knowledge-decision-edit-toggle')));
      await _settle(tester);
      await tester.ensureVisible(
        find.byKey(const Key('knowledge-decision-cite-bcr')),
      );
      await tester.tap(find.byKey(const Key('knowledge-decision-cite-bcr')));
      await _settle(tester);
      await tester.tap(find.text('Asset allocation'));
      await _settle(tester);
      expect(find.byKey(const Key('knowledge-source-link')), findsNothing);
      expect(
        find.textContaining('Note text is available offline.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('bcr-cite-note')));
      await tester.tap(find.byKey(const Key('bcr-cite-note')));
      await _settle(tester);
      // Inserting evidence only changes the draft; the ordinary Save commits it.
      expect(
        (await decisions.findDecision(
          ownerUserId: 'owner',
          id: 'decision',
        ))!.rationaleMd,
        'Keep a buffer.',
      );
      await tester.tap(find.text('Save').hitTestable());
      await _settle(tester);
      final saved = (await decisions.findDecision(
        ownerUserId: 'owner',
        id: 'decision',
      ))!;
      expect(saved.rationaleMd, contains('60%'));
      expect(saved.rationaleMd, contains('Asset allocation · Research'));
      expect(saved.rationaleMd, isNot(contains('](null)')));
      expect(saved.rationaleMd, contains(snapshot.notes.single.fingerprint));
      expect(saved.rationaleMd, contains('${snapshot.id}/note-0'));

      client.snapshot = makeBcrArchive(body: 'Now 90%.');
      client.head = 'b' * 40;
      final connection = (await sources.listConnections('owner')).single;
      final sync = await container.read(bcrKnowledgeSyncServiceProvider.future);
      await sync.sync(connection, manual: true);
      expect(
        (await decisions.findDecision(
          ownerUserId: 'owner',
          id: 'decision',
        ))!.rationaleMd,
        saved.rationaleMd,
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    },
  );

  testWidgets(
    'an open reader hides title and body when its source is removed',
    (tester) async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final repository = BcrKnowledgeRepository(db);
      final url = normalizeBcrLibraryUrl('https://notes.example.com/knowledge');
      await repository.importArchive(
        owner: 'owner',
        label: 'Research',
        libraryUrl: url,
        archive: makeBcrArchive(),
        expectedCacheRevision: null,
        importToken: await repository.beginImport(
          owner: 'owner',
          libraryUrl: url,
        ),
      );
      final source = (await repository.listSources('owner')).single;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => db),
            currentUserIdProvider.overrideWithValue(() async => 'owner'),
          ],
          child: MaterialApp(
            builder: buildTestAppTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: BcrKnowledgeReader(
              hit: BcrKnowledgeHit(source: source, note: source.notes.single),
            ),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('Asset allocation'), findsOneWidget);
      expect(
        find.text('https://notes.example.com/knowledge?note=note-0'),
        findsOneWidget,
      );
      await repository.removeSource(
        owner: 'owner',
        id: source.id,
        expectedCacheRevision: source.cacheRevision,
      );
      await _settle(tester);
      expect(find.text('Asset allocation'), findsNothing);
      expect(find.textContaining('60%'), findsNothing);
      expect(find.byKey(const Key('bcr-cite-note')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    },
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 70));
  }
}
