import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/ui/execution_search_sheet.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

class _Repository extends Fake implements ExecutionRepository {
  final requests = <Completer<List<ExecutionSearchHit>>>[];
  @override
  Future<List<ExecutionSearchHit>> search({
    required String ownerUserId,
    required String query,
    int limit = 50,
  }) {
    final request = Completer<List<ExecutionSearchHit>>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  testWidgets('search retries failure and discards stale responses', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          executionOwnerUserIdProvider.overrideWith((_) async => 'owner'),
          executionRepositoryProvider.overrideWith((_) async => repository),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showExecutionSearchSheet(context: context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'first');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    repository.requests.single.completeError(StateError('test failure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(repository.requests, hasLength(2));
    await tester.enterText(find.byType(EditableText), 'second');
    repository.requests[1].complete(const [
      ExecutionSearchHit(
        kind: ExecutionEntryKind.action,
        id: 'old',
        title: 'Stale result',
        status: 'todo',
      ),
    ]);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Stale result'), findsNothing);
    repository.requests[2].complete(const [
      ExecutionSearchHit(
        kind: ExecutionEntryKind.action,
        id: 'new',
        title: 'Current result',
        status: 'todo',
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Current result'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
