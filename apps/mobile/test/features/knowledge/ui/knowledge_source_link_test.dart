import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/knowledge/ui/widgets/knowledge_source_link.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('renders a canonical host and opens only the normalized source', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      _wrap(
        KnowledgeSourceLink(
          sourceUrl: 'HTTPS://WWW.Example.COM:443/article#section',
          launcher: (uri) async {
            opened = uri;
            return true;
          },
        ),
      ),
    );

    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('https://www.example.com/article'), findsOneWidget);
    await tester.tap(find.byKey(const Key('knowledge-source-link')));
    await tester.pump();

    expect(opened?.toString(), 'https://www.example.com/article');
  });

  testWidgets('does not render unsafe sources', (tester) async {
    await tester.pumpWidget(
      _wrap(const KnowledgeSourceLink(sourceUrl: 'ftp://example.com/file')),
    );

    expect(find.byKey(const Key('knowledge-source-link')), findsNothing);
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(
        body: Center(child: SizedBox(width: 360, child: child)),
      ),
    ),
  );
}
