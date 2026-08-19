import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/ui/wealth/wealth_action_panel.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap() {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'CN'),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWealthActionPanel(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('wealth action panel fits a compact mobile viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('添加资产项目'), findsOneWidget);
    expect(find.byType(AppActionSheetTile), findsNWidgets(3));
    expect(find.byType(SoftCard), findsNothing);

    await tester.tap(find.text('资产'));
    await tester.pumpAndSettle();

    expect(find.text('选择最符合这项资产的类型。'), findsOneWidget);
    expect(find.byType(AppActionSheetTile), findsNWidgets(5));
  });
}
