import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/knowledge_repository.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_library_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('matchesKnowledgeLibraryDateFilter', () {
    test('matches recent week and month buckets', () {
      final now = DateTime.utc(2026, 6, 7, 12);

      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 6, 1),
          KnowledgeLibraryDateFilter.week,
          now,
        ),
        isTrue,
      );
      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 5, 8),
          KnowledgeLibraryDateFilter.month,
          now,
        ),
        isTrue,
      );
    });

    test('excludes dates outside the selected bucket', () {
      final now = DateTime.utc(2026, 6, 7, 12);

      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 6, 16),
          KnowledgeLibraryDateFilter.week,
          now,
        ),
        isFalse,
      );
      expect(
        matchesKnowledgeLibraryDateFilter(
          DateTime.utc(2026, 7, 8),
          KnowledgeLibraryDateFilter.month,
          now,
        ),
        isFalse,
      );
    });
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
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Keep raw observations and sources'), findsOneWidget);

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
    await tester.pumpAndSettle();

    expect(find.text('All · 0 items'), findsOneWidget);
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
    expect(find.text('Repeat actions on a cadence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        activeUserIdProvider.overrideWithValue('user-1'),
        currentUserIdProvider.overrideWithValue(() async => 'user-1'),
        knowledgeRepositoryProvider.overrideWith(
          (_) async => _EmptyKnowledgeRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en', 'US'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: FTheme(
          data: FThemes.slate.light.desktop,
          child: const KnowledgeLibraryPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _EmptyKnowledgeRepository implements KnowledgeRepository {
  @override
  Stream<List<KnowledgeDecision>> watchDecisions({
    required String ownerUserId,
    int? limit,
  }) => Stream<List<KnowledgeDecision>>.value(const <KnowledgeDecision>[]);

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
