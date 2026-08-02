import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';
import 'package:naviwealth/features/knowledge/ui/knowledge_inbox_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  Future<void> pumpInbox(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          knowledgeInboxNotesProvider.overrideWith(
            (_) => Stream<List<KnowledgeNote>>.value(const <KnowledgeNote>[]),
          ),
        ],
        child: FTheme(
          data: FThemes.slate.light.desktop,
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en', 'US'),
            home: const KnowledgeInboxPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('groups Knowledge AI shortcuts in one adaptive menu', (
    tester,
  ) async {
    await pumpInbox(tester);

    expect(find.byIcon(FLucideIcons.sparkles), findsOneWidget);
    expect(find.byIcon(FLucideIcons.gitMerge), findsNothing);
    expect(find.text('Deduplicate'), findsNothing);

    await tester.tap(find.byIcon(FLucideIcons.ellipsis));
    await tester.pumpAndSettle();

    expect(find.text('Deduplicate'), findsOneWidget);
    expect(find.text('Weekly review'), findsOneWidget);
    expect(find.text('Search knowledge'), findsOneWidget);
  });

  testWidgets('keeps capture in the shared shell header', (tester) async {
    await pumpInbox(tester);

    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Inbox · KnowledgeOS'), findsNothing);
    expect(find.byIcon(FLucideIcons.plus), findsOneWidget);
  });
}
