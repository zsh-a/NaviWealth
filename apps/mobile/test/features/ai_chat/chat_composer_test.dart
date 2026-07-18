import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/ai_chat/ui/chat_composer.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('idle composer uses localized copy and sends non-empty text', (
    tester,
  ) async {
    final sent = <String>[];
    var cancelled = 0;

    await _pumpComposer(
      tester,
      locale: const Locale('en'),
      isStreaming: false,
      onSend: sent.add,
      onCancel: () => cancelled++,
    );

    expect(
      find.text('Ask NaviWealth about finance, knowledge, health, or plans'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(FLucideIcons.arrowUp));
    await tester.pump(const Duration(milliseconds: 120));
    expect(sent, isEmpty);

    await tester.enterText(find.byType(EditableText), 'Summarize my month');
    await tester.pump();
    await tester.tap(find.byIcon(FLucideIcons.arrowUp));
    await tester.pump(const Duration(milliseconds: 120));

    expect(sent, <String>['Summarize my month']);
    expect(find.text('Summarize my month'), findsNothing);
    expect(cancelled, 0);
  });

  testWidgets('streaming composer disables input and exposes stop action', (
    tester,
  ) async {
    final sent = <String>[];
    var cancelled = 0;

    await _pumpComposer(
      tester,
      locale: const Locale('zh'),
      isStreaming: true,
      initialText: 'ignored draft',
      onSend: sent.add,
      onCancel: () => cancelled++,
    );

    expect(find.text('正在生成回答…'), findsOneWidget);

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.readOnly, isTrue);

    await tester.tap(find.byIcon(FLucideIcons.square));
    await tester.pump(const Duration(milliseconds: 120));

    expect(cancelled, 1);
    expect(sent, isEmpty);
  });
}

Future<void> _pumpComposer(
  WidgetTester tester, {
  required Locale locale,
  required bool isStreaming,
  required ValueChanged<String> onSend,
  required VoidCallback onCancel,
  String? initialText,
}) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatComposer(
              isStreaming: isStreaming,
              initialText: initialText,
              onSend: onSend,
              onCancel: onCancel,
            ),
          ),
        ),
      ),
    ),
  );
}
