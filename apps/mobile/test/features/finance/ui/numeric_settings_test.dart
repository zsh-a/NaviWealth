import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/fire/data/fire_plan_repository.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';
import 'package:naviwealth/features/finance/fire/domain/fire_plan.dart';
import 'package:naviwealth/features/finance/ui/settings/fire_stress_settings_page.dart';
import 'package:naviwealth/features/finance/ui/settings/monthly_expense_settings_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Plans extends Fake implements FirePlanRepository {
  final List<FirePlan> writes = [];
  @override
  Future<FirePlan> upsert(FirePlan plan) async {
    writes.add(plan);
    return plan;
  }
}

Widget _host(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: FTheme(
          data: FTheme.neutral.light.desktop,
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );

Future<void> _enterAndBlur(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('invalid stress amounts never overwrite the saved amount', (
    tester,
  ) async {
    final plans = _Plans();
    final container = ProviderContainer(
      overrides: [
        firePlanProvider.overrideWithValue(
          FirePlan.unset(baseCurrency: 'USD').copyWith(
            riskSettings: const FireRiskSettings(oneOffShockAmount: 500),
          ),
        ),
        firePlanRepositoryProvider.overrideWith((_) async => plans),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container, const FireStressSettings()));
    await tester.pumpAndSettle();
    for (final value in ['abc', '-1', '']) {
      await _enterAndBlur(tester, value);
      expect(plans.writes, isEmpty);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        value,
      );
      expect(find.text('USD'), findsOneWidget);
    }
    await _enterAndBlur(tester, '0');
    expect(plans.writes.single.riskSettings.oneOffShockAmount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monthly override keeps invalid edits visible without saving', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'naviwealth.expense.monthly.override': '500',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dashboardBaseCurrencyProvider.overrideWithValue('USD'),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container, const MonthlyExpenseSettings()));
    await tester.pumpAndSettle();
    await _enterAndBlur(tester, 'abc');
    expect(prefs.getString('naviwealth.expense.monthly.override'), '500');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'abc',
    );
    await _enterAndBlur(tester, '625.25');
    expect(prefs.getString('naviwealth.expense.monthly.override'), '625.25');
    await _enterAndBlur(tester, '');
    expect(prefs.getString('naviwealth.expense.monthly.override'), isNull);
    expect(tester.takeException(), isNull);
  });
}
