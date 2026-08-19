import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/accounts/ui/account_category_picker.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh', 'CN'),
    home: FTheme(
      data: FTheme.neutral.light.desktop,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('account category picker does not overflow at 4-column width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 600,
          child: AccountCategoryPicker(
            value: AccountCategory.bank,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('银行'), findsOneWidget);
  });
}
