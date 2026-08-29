import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/shell/master_detail_layout.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_route_paths.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_decision_detail_page.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_library_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('reveals edit and type action on right swipe', (tester) async {
    await _pumpLibrary(
      tester,
      width: 390,
      repository: _EmptyKnowledgeRepository(
        decisions: [_decision('review-me', DecisionStatus.active)],
      ),
    );

    final tile = find.byKey(
      const ValueKey<String>('lib-tile-decision:review-me'),
    );
    expect(tile, findsOneWidget);

    await tester.drag(tile, const Offset(150, 0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('app-swipe-action.edit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('app-swipe-action.review')),
      findsOneWidget,
    );
  });

  testWidgets('uses one immediate contextual filter', (tester) async {
    await _pumpLibrary(
      tester,
      width: 390,
      repository: _EmptyKnowledgeRepository(
        decisions: [
          _decision('draft', DecisionStatus.draft),
          _decision('active', DecisionStatus.active),
        ],
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-library.type-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Decisions').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsWidgets);
    expect(find.text('Draft'), findsWidgets);
    expect(find.text('Date'), findsNothing);
    expect(find.text('Tags and scope'), findsNothing);
    expect(find.text('Clear filters'), findsNothing);

    await tester.tap(find.text('Active').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('lib-tile-active')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('lib-tile-draft')), findsNothing);
  });

  testWidgets('uses a compact, descriptive type picker on mobile', (
    tester,
  ) async {
    await _pumpLibrary(tester, width: 390);

    expect(
      find.byKey(const ValueKey<String>('knowledge-library.type-picker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('knowledge-library.segmented-types')),
      findsNothing,
    );
    expect(find.text('All · 0 items'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-library.type-picker')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.text('Knowledge type'), findsOneWidget);
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Decisions'), findsOneWidget);
    expect(find.text('Sources'), findsNothing);
    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Action'), findsNothing);

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    expect(find.text('Notes · 0 items'), findsOneWidget);
    expect(find.text('No Notes in the library yet'), findsOneWidget);
    expect(find.text('New Note'), findsOneWidget);
  });

  testWidgets('offers global search when a scoped mobile search is empty', (
    tester,
  ) async {
    await _pumpLibrary(tester, width: 390);

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-library.type-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(FTextField), 'portfolio');
    await tester.pump(const Duration(milliseconds: 160));

    expect(find.text('Search all knowledge'), findsOneWidget);
    await tester.tap(find.text('Search all knowledge'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80), EnginePhase.paint);
    }

    expect(find.text('All · 0 items'), findsOneWidget);
  });

  testWidgets('legacy object types stay out of the primary picker', (
    tester,
  ) async {
    await _pumpLibrary(tester, width: 390);

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-library.type-picker')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Concepts'), findsNothing);
    expect(find.text('Experiments'), findsNothing);
    expect(find.text('Routines'), findsNothing);
    expect(find.text('Assumptions'), findsNothing);
    expect(find.text('New Concept'), findsNothing);
  });

  testWidgets('keeps the taxonomy behind one picker on wide layouts', (
    tester,
  ) async {
    await _pumpLibrary(tester, width: 1200);

    expect(
      find.byKey(const ValueKey<String>('knowledge-library.type-picker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('knowledge-library.segmented-types')),
      findsNothing,
    );
  });

  testWidgets('type picker remains usable on a narrow large-text phone', (
    tester,
  ) async {
    await _pumpLibrary(tester, width: 320, textScale: 1.6);

    await tester.tap(
      find.byKey(const ValueKey<String>('knowledge-library.type-picker')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppSheet), findsOneWidget);
    expect(find.text('Keep raw observations and sources'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a browsing detail pane on desktop', (tester) async {
    await _pumpLibrary(tester, width: 1400, withRouter: true);

    expect(find.byType(MasterDetailLayout), findsOneWidget);
    expect(find.textContaining('Select an item'), findsOneWidget);
  });

  testWidgets('updates same-kind desktop detail without retaining old state', (
    tester,
  ) async {
    final repository = _EmptyKnowledgeRepository(
      decisions: [
        _decision('first', DecisionStatus.active),
        _decision('second', DecisionStatus.active),
      ],
    );
    await _pumpLibrary(
      tester,
      width: 1400,
      withRouter: true,
      repository: repository,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('lib-tile-decision:first')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<KnowledgeDecisionDetailPage>(
            find.byType(KnowledgeDecisionDetailPage),
          )
          .decisionId,
      'first',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('lib-tile-decision:second')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<KnowledgeDecisionDetailPage>(
            find.byType(KnowledgeDecisionDetailPage),
          )
          .decisionId,
      'second',
    );
  });

  testWidgets('decision form distinguishes validation from saving', (
    tester,
  ) async {
    await _pumpLibrary(tester, width: 390);

    await tester.tap(find.byIcon(FLucideIcons.plus).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Decision'));
    await tester.pumpAndSettle();

    expect(find.text('Enter at least two different options.'), findsOneWidget);
    expect(find.byType(FCircularProgress), findsNothing);

    final fields = find.descendant(
      of: find.byType(AppSheet),
      matching: find.byType(EditableText),
    );
    await tester.enterText(fields.at(0), 'Which direction should I choose?');
    await tester.enterText(fields.at(1), 'Option A');
    await tester.enterText(fields.at(3), 'Option B');
    await tester.pump();

    expect(find.text('Enter at least two different options.'), findsNothing);
    expect(find.text('Choose the option you decided to take.'), findsOneWidget);
    await tester.tap(find.byType(FRadio).first);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Choose the option you decided to take.'), findsNothing);
    expect(find.byType(FCircularProgress), findsNothing);
  });
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
  KnowledgeRepository? repository,
  bool withRouter = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();

  final page = FTheme(
    data: FTheme.neutral.light.desktop,
    child: const KnowledgeLibraryPage(),
  );
  GoRouter? router;
  final Widget app;
  if (withRouter) {
    router = GoRouter(
      initialLocation: KnowledgeRoutes.library,
      routes: [GoRoute(path: KnowledgeRoutes.library, builder: (_, _) => page)],
    );
    addTearDown(router.dispose);
    app = MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
    );
  } else {
    app = MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: page,
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        activeUserIdProvider.overrideWithValue('user-1'),
        currentUserIdProvider.overrideWithValue(() async => 'user-1'),
        knowledgeRepositoryProvider.overrideWith(
          (_) async => repository ?? _EmptyKnowledgeRepository(),
        ),
      ],
      child: app,
    ),
  );
  await tester.pumpAndSettle();
}

KnowledgeDecision _decision(String id, DecisionStatus status) {
  final at = DateTime.utc(2026, 8, 2);
  return KnowledgeDecision(
    id: id,
    question: id,
    options: const <DecisionOption>[],
    selectedLabel: '',
    rationaleMd: '',
    principleIds: const <String>[],
    assumptionIds: const <String>[],
    status: status,
    decidedAt: at,
    sync: SyncMeta(
      ownerUserId: 'user-1',
      updatedAt: at,
      updatedByDevice: 'test-device',
      hlc: Hlc.zero('test-device'),
    ),
  );
}

class _EmptyKnowledgeRepository implements KnowledgeRepository {
  _EmptyKnowledgeRepository({this.decisions = const <KnowledgeDecision>[]});

  final List<KnowledgeDecision> decisions;

  @override
  Future<KnowledgeDecision?> findDecision({
    required String ownerUserId,
    required String id,
  }) async => decisions.where((item) => item.id == id).firstOrNull;

  @override
  Future<List<KnowledgeRelation>> listRelationsFrom({
    required String ownerUserId,
    required String fromKind,
    required String fromId,
  }) async => const <KnowledgeRelation>[];

  @override
  Stream<List<KnowledgeDecision>> watchDecisions({
    required String ownerUserId,
    int? limit,
  }) => Stream<List<KnowledgeDecision>>.value(decisions);

  @override
  Stream<List<KnowledgePrinciple>> watchPrinciples({
    required String ownerUserId,
  }) => Stream<List<KnowledgePrinciple>>.value(const <KnowledgePrinciple>[]);

  @override
  Stream<List<KnowledgeAssumption>> watchAssumptions({
    required String ownerUserId,
  }) => Stream<List<KnowledgeAssumption>>.value(const <KnowledgeAssumption>[]);

  @override
  Stream<List<KnowledgeNote>> watchNotes({
    required String ownerUserId,
    int? limit,
  }) => Stream<List<KnowledgeNote>>.value(const <KnowledgeNote>[]);

  @override
  Stream<List<KnowledgeConcept>> watchConcepts({required String ownerUserId}) =>
      Stream<List<KnowledgeConcept>>.value(const <KnowledgeConcept>[]);

  @override
  Stream<List<KnowledgeExperiment>> watchExperiments({
    required String ownerUserId,
  }) => Stream<List<KnowledgeExperiment>>.value(const <KnowledgeExperiment>[]);

  @override
  Stream<List<KnowledgeRoutine>> watchRoutines({required String ownerUserId}) =>
      Stream<List<KnowledgeRoutine>>.value(const <KnowledgeRoutine>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}
