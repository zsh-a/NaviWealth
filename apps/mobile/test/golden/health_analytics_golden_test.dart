import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/health/ui/health_today_page.dart';
import 'package:naviwealth/features/health/ui/health_trend_page.dart';

import '../features/health/ui/health_test_fixture.dart';
import '_golden_setup.dart';

void main() {
  for (final variant in [GoldenTheme.light, GoldenTheme.dark]) {
    for (final (name, path, page) in [
      ('health_populated_today', '/health', const HealthTodayPage()),
      ('health_trends_overview', '/health/trend', const HealthTrendPage()),
      (
        'health_sleep_detail',
        '/health/trend',
        HealthTrendPage.fromQuery(const {'metric': 'sleep_session'}),
      ),
      (
        'health_weight_detail',
        '/health/trend',
        HealthTrendPage.fromQuery(const {'metric': 'weight'}),
      ),
    ]) {
      testVisualGolden('$name ${variant.name}', (tester) async {
        final fixture = await HealthTestFixture.create();
        addTearDown(fixture.db.close);
        await pumpAndSnapshotMobile(
          tester,
          name: name,
          routePath: path,
          variant: variant,
          child: page,
          overrides: fixture.overrides,
          locale: const Locale('zh'),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
  testVisualGolden('health detail at double text size', (tester) async {
    final fixture = await HealthTestFixture.create();
    addTearDown(fixture.db.close);
    await pumpAndSnapshotMobile(
      tester,
      name: 'health_sleep_large_text',
      routePath: '/health/trend',
      variant: GoldenTheme.dark,
      locale: const Locale('zh'),
      overrides: fixture.overrides,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: HealthTrendPage.fromQuery(const {'metric': 'sleep_session'}),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
