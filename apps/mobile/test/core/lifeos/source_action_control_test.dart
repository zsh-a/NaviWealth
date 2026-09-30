import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/lifeos/action_dispatcher.dart';
import 'package:naviwealth/core/lifeos/ui/source_action_control.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

const _source = (rowFamily: 'know:knowledge_decisions', rowId: 'decision');

Widget _wrap({
  required LifeSourceActionReader read,
  required LifeActionDispatcher dispatch,
  Future<void> Function(String)? onCreated,
}) => ProviderScope(
  overrides: [
    lifeSourceActionReaderProvider.overrideWithValue(read),
    lifeActionDispatcherProvider.overrideWithValue(dispatch),
  ],
  child: MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (_, child) =>
        FTheme(data: FTheme.neutral.light.desktop, child: child!),
    home: Scaffold(
      body: SourceActionControl(
        source: _source,
        createLabel: 'Create action',
        openLabel: 'Open action',
        confirmTitle: 'Create?',
        confirmBody: 'For this source',
        successMessage: 'Created',
        openAfterCreate: false,
        onCreated: onCreated,
        buildDraft: (replaces) => LifeActionDraft(
          title: 'Follow up',
          note: 'Evidence',
          sourceDomain: 'knowledge',
          sourceRowFamily: _source.rowFamily,
          sourceRowId: _source.rowId,
          replacesActionId: replaces,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'completed action remains linked and cannot be silently recreated',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _wrap(
          read: (_) async => const LifeLinkedAction(
            id: 'completed',
            state: LifeActionState.done,
          ),
          dispatch: (_) async {
            calls++;
            return 'new';
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Open action'), findsOneWidget);
      expect(find.text('Create action'), findsNothing);
      expect(calls, 0);
    },
  );

  testWidgets(
    'replacement requires explicit confirmation and passes exact dropped id',
    (tester) async {
      LifeLinkedAction? linked = const LifeLinkedAction(
        id: 'old',
        state: LifeActionState.dropped,
      );
      LifeActionDraft? captured;
      await tester.pumpWidget(
        _wrap(
          read: (_) async => linked,
          dispatch: (draft) async {
            captured = draft;
            linked = const LifeLinkedAction(
              id: 'new',
              state: LifeActionState.todo,
            );
            return 'new';
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create replacement action'));
      await tester.pumpAndSettle();
      expect(captured, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(captured, isNull);
      await tester.tap(find.text('Create replacement action'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create replacement action').last);
      await tester.pumpAndSettle();
      expect(captured?.replacesActionId, 'old');
      expect(find.text('Create replacement action'), findsNothing);
      expect(
        find.text(
          lookupAppLocalizations(const Locale('en')).executionStatusTodo,
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets(
    'bookkeeping failure can retry without creating another durable action',
    (tester) async {
      var calls = 0;
      var links = 0;
      LifeLinkedAction? linked;
      await tester.pumpWidget(
        _wrap(
          read: (_) async => linked,
          dispatch: (_) async {
            calls++;
            linked = const LifeLinkedAction(
              id: 'durable',
              state: LifeActionState.todo,
            );
            return 'durable';
          },
          onCreated: (_) async {
            links++;
            if (links == 1) throw StateError('private storage');
          },
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<FButton>(
        find.widgetWithText(FButton, 'Create action'),
      );
      button.onPress!();
      button.onPress!();
      await tester.pumpAndSettle();
      expect(find.text('Create?'), findsOneWidget);
      await tester.tap(find.text('Create action').last);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(links, 1);
      expect(find.byType(AppStatusBanner), findsOneWidget);
      final context = tester.element(find.byType(SourceActionControl));
      ProviderScope.containerOf(context)
          .invalidate(lifeLinkedActionProvider(_source));
      await tester.pumpAndSettle();
      expect(find.text('Create action'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(links, 2);
      expect(find.byType(AppStatusBanner), findsNothing);
      await tester.pump(const Duration(seconds: 7));
    },
  );

  testWidgets('failed lookup offers read retry and never offers creation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        read: (_) async => throw StateError('read failed'),
        dispatch: (_) async => 'new',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create action'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });
}
