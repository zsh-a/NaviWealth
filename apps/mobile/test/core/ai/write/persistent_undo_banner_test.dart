import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/ai/write/drift_undo_stack.dart';
import 'package:naviwealth/core/ai/write/persisted_undo_dispatcher.dart';
import 'package:naviwealth/core/ai/write/persistent_undo_banner.dart';
import 'package:naviwealth/core/ai/write/providers.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class _RecordingUndoDispatcher implements PersistedUndoDispatcher {
  final tokens = <String>[];

  @override
  Future<PersistedUndoDispatchResult> undo(String token) async {
    tokens.add(token);
    return const PersistedUndoDispatchResult(
      PersistedUndoDispatchStatus.applied,
    );
  }
}

void main() {
  testWidgets('dynamic summary is a live region beside an undo button', (
    tester,
  ) async {
    const summary =
        'Imported transaction was assigned to the groceries category';
    const token = 'undo-token';
    final controller = StreamController<List<PersistedUndoEntry>>();
    final dispatcher = _RecordingUndoDispatcher();
    final semantics = tester.ensureSemantics();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          undoEntriesStreamProvider.overrideWith((_) => controller.stream),
          persistedUndoDispatcherProvider.overrideWithValue(dispatcher),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FThemes.slate.light.desktop,
            child: const Scaffold(bottomNavigationBar: PersistentUndoBanner()),
          ),
        ),
      ),
    );

    controller.add(const <PersistedUndoEntry>[]);
    await tester.pumpAndSettle();
    expect(find.text(summary), findsNothing);
    expect(tester.takeException(), isNull);

    controller.add([
      PersistedUndoEntry(
        token: token,
        kind: 'test',
        payload: const {'summary_zh': summary},
        createdAt: DateTime.utc(2026, 7, 10),
        expiresAt: null,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final summaryNodes = find.semantics.byLabel(summary).evaluate().toList();
    expect(summaryNodes, hasLength(1));
    expect(
      summaryNodes.single.getSemanticsData().flagsCollection.isLiveRegion,
      isTrue,
    );

    final undoFinder = find.semantics.byLabel('Undo');
    final undoNodes = undoFinder.evaluate().toList();
    expect(undoNodes, hasLength(1));
    final undoData = undoNodes.single.getSemanticsData();
    expect(undoData.flagsCollection.isButton, isTrue);
    expect(undoData.flagsCollection.isEnabled, ui.Tristate.isTrue);
    expect(undoData.hasAction(SemanticsAction.tap), isTrue);

    final mergedFinder = find.semantics.byPredicate((node) {
      final label = node.label;
      return label.contains(summary) && label.contains('Undo');
    });
    expect(mergedFinder.evaluate(), isEmpty);

    tester.semantics.tap(undoFinder);
    await tester.pump();
    expect(dispatcher.tokens, [token]);

    controller.add(const <PersistedUndoEntry>[]);
    await tester.pumpAndSettle();
    expect(find.text(summary), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
