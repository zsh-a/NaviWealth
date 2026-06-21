import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_object_detail_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../core/persistence/test_database.dart';

void main() {
  late AppDatabase db;
  late InMemoryOutboxStore outbox;
  late KnowledgeRepository repo;

  const owner = 'u-test';
  final created = DateTime.utc(2026, 1, 1);

  setUp(() {
    db = makeTestDatabase();
    outbox = InMemoryOutboxStore();
    repo = KnowledgeRepository(db: db, outbox: outbox);
  });

  tearDown(() async => db.close());

  SyncMeta meta() => SyncMeta(
    ownerUserId: owner,
    updatedAt: created,
    updatedByDevice: 'dev-test',
    hlc: Hlc.zero('dev-test'),
  );

  KnowledgeConcept concept({
    required String id,
    required String name,
    List<String> aliases = const <String>[],
    List<String> related = const <String>[],
  }) {
    return KnowledgeConcept(
      id: id,
      name: name,
      aliases: aliases,
      summaryMd: '',
      relatedConceptIds: related,
      createdAt: created,
      sync: meta(),
    );
  }

  Future<void> pumpDetail(WidgetTester tester, String id) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeRepositoryProvider.overrideWith((ref) async => repo),
          knowledgeOwnerUserIdProvider.overrideWith((ref) async => owner),
        ],
        child: FTheme(
          data: FThemes.slate.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: Scaffold(
              body: KnowledgeObjectDetailPage(kind: 'concept', id: id),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('renders a concept graph for related concepts', (tester) async {
    await repo.upsertConcept(
      concept(
        id: 'fire',
        name: 'FIRE',
        aliases: const ['Financial Independence'],
        related: const ['margin', 'xirr'],
      ),
    );
    await repo.upsertConcept(
      concept(id: 'margin', name: 'Margin of Safety', aliases: const ['MOS']),
    );
    await repo.upsertConcept(concept(id: 'xirr', name: 'XIRR'));

    await pumpDetail(tester, 'fire');

    expect(find.byKey(const ValueKey('knowledge-concept-graph')), findsOne);
    expect(find.text('FIRE'), findsWidgets);
    expect(find.text('Margin of Safety'), findsWidgets);
    expect(find.text('XIRR'), findsWidgets);
    expect(find.text('MOS'), findsWidgets);
  });

  testWidgets('omits the concept graph when there are no related concepts', (
    tester,
  ) async {
    await repo.upsertConcept(concept(id: 'solo', name: 'Solo Concept'));

    await pumpDetail(tester, 'solo');

    expect(find.byKey(const ValueKey('knowledge-concept-graph')), findsNothing);
    expect(find.text('Solo Concept'), findsWidgets);
  });
}
