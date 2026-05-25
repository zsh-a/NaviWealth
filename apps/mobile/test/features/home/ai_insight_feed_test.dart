import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/home/domain/insight_models.dart';
import 'package:naviwealth/features/home/ui/ai_insight_feed.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(List<InsightItem> insights, {SharedPreferences? prefs}) {
  return ProviderScope(
    overrides: [
      if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en', 'US'),
      home: FTheme(
        data: FThemes.slate.light.desktop,
        child: Scaffold(
          body: SingleChildScrollView(child: AiInsightFeed(insights: insights)),
        ),
      ),
    ),
  );
}

InsightItem _maturityInsight({int count = 2, int days = 7}) {
  return InsightItem(
    icon: FLucideIcons.calendar,
    kind: InsightKind.maturity,
    maturityCount: count,
    maturityDays: days,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('collapses to nothing when the insight list is empty', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const []));
    await tester.pumpAndSettle();

    // Empty feed renders an empty SizedBox — no icon, no headline.
    expect(find.byIcon(FLucideIcons.calendar), findsNothing);
  });

  testWidgets('renders the section header when at least one insight exists', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_wrap([_maturityInsight()], prefs: prefs));
    await tester.pumpAndSettle();

    // The localized section title ("AI Insights" / "AI 洞察") appears
    // above the feed.
    expect(find.byIcon(FLucideIcons.calendar), findsOneWidget);
  });

  testWidgets('renders one card per insight', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      _wrap([
        _maturityInsight(),
        _maturityInsight(count: 5, days: 14),
        _maturityInsight(count: 1, days: 30),
      ], prefs: prefs),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(FLucideIcons.calendar), findsNWidgets(3));
  });
}
