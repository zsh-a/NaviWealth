import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/data/chat_history_store.dart';
import 'package:naviwealth/features/ai_chat/data/chat_repository.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart';
import 'package:naviwealth/features/ai_chat/data/runtime_routing_api_client.dart';
import 'package:naviwealth/features/ai_chat/domain/chat_models.dart';
import 'package:naviwealth/features/ai_chat/ui/sessions/sessions_panel.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../core/persistence/test_database.dart';

void main() {
  testWidgets('history sheet loads rows lazily within a large recency group', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = makeTestDatabase();
    addTearDown(db.close);
    final store = ChatHistoryStore(db);
    addTearDown(store.dispose);
    final now = DateTime.now().subtract(const Duration(days: 90));
    await db.transaction(() async {
      for (var i = 0; i < 300; i++) {
        final created = now.subtract(Duration(minutes: i));
        await store.insertSession(
          ChatSession(
            id: 's$i',
            ownerUserId: 'u1',
            title: 'Session ${i.toString().padLeft(4, '0')}',
            createdAt: created,
            updatedAt: created,
          ),
        );
      }
    });
    final repository = ChatRepository(
      store: store,
      api: const RuntimeRoutingAiChatApiClient(),
      sessionReader: () => null,
    );
    String? selected;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeUserIdProvider.overrideWith((_) => 'u1'),
          chatRepositoryProvider.overrideWith((_) async => repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: FTheme(
            data: buildAppForuiTheme(brightness: Brightness.light, touch: true),
            child: Builder(
              builder: (context) => Scaffold(
                body: FButton(
                  onPress: () => showAppFormSheet<void>(
                    context: context,
                    builder: (_) => SizedBox(
                      height: 600,
                      child: SessionsPanel(
                        activeSessionId: null,
                        onSelect: (id) => selected = id,
                        onNew: () {},
                      ),
                    ),
                  ),
                  child: const Text('Open history'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open history'));
    await tester.pumpAndSettle();
    expect(find.text('Session 0000'), findsOneWidget);
    // Most of the 300 offscreen rows must remain unbuilt, including within
    // the first visible group. Counting widgets catches grouped Columns.
    expect(find.byType(AppDismissible).evaluate().length, lessThan(40));
    expect(find.text('Session 0299'), findsNothing);
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Session 0299'),
      1000,
      scrollable: scrollable,
    );
    await tester.tap(find.text('Session 0299'));
    await tester.pumpAndSettle();
    expect(selected, 's299');
    await tester.enterText(find.byType(FTextField), '0299');
    await tester.pumpAndSettle();
    expect(find.byType(AppDismissible), findsOneWidget);
    expect(find.text('Session 0299'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
