import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../golden/_golden_setup.dart';

enum ReadmeScreenshotProfile { mobile, featureCard, desktop }

extension ReadmeScreenshotProfileData on ReadmeScreenshotProfile {
  Size get logicalSize => switch (this) {
    ReadmeScreenshotProfile.mobile => const Size(390, 844),
    ReadmeScreenshotProfile.featureCard => const Size(390, 440),
    ReadmeScreenshotProfile.desktop => const Size(1280, 900),
  };

  double get devicePixelRatio => switch (this) {
    ReadmeScreenshotProfile.mobile || ReadmeScreenshotProfile.featureCard => 2,
    ReadmeScreenshotProfile.desktop => 1,
  };

  TargetPlatform get platform => switch (this) {
    ReadmeScreenshotProfile.mobile ||
    ReadmeScreenshotProfile.featureCard => TargetPlatform.iOS,
    ReadmeScreenshotProfile.desktop => TargetPlatform.linux,
  };

  bool get touch => this != ReadmeScreenshotProfile.desktop;
  bool get compact => this == ReadmeScreenshotProfile.desktop;
}

Future<void> pumpReadmeScreenshot(
  WidgetTester tester, {
  required ReadmeScreenshotProfile profile,
  required String goldenPath,
  required Widget child,
  List<Override> overrides = const [],
  Locale locale = const Locale('zh'),
}) async {
  await loadGoldenFonts();
  final logicalSize = profile.logicalSize;
  final dpr = profile.devicePixelRatio;
  await tester.binding.setSurfaceSize(logicalSize);
  tester.view
    ..physicalSize = Size(logicalSize.width * dpr, logicalSize.height * dpr)
    ..devicePixelRatio = dpr;
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  final router = GoRouter(
    routes: <RouteBase>[GoRoute(path: '/', builder: (_, _) => child)],
    errorBuilder: (_, _) => const SizedBox.shrink(),
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MarketColorsScope(
        colors: GoldenTheme.dark.marketColors,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(
            compact: profile.compact,
          ).copyWith(platform: profile.platform),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          routerConfig: router,
          builder: (context, routedChild) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.noScaling,
            ),
            child: FTheme(
              data: buildAppForuiTheme(
                brightness: Brightness.dark,
                touch: profile.touch,
              ),
              child: routedChild!,
            ),
          ),
        ),
      ),
    ),
  );

  for (final duration in const <Duration>[
    Duration.zero,
    Duration(milliseconds: 100),
    Duration(milliseconds: 200),
    Duration(milliseconds: 200),
  ]) {
    await tester.pump(duration);
  }

  expect(tester.takeException(), isNull);
  expect(
    tester.view.physicalSize,
    Size(logicalSize.width * dpr, logicalSize.height * dpr),
  );
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void readmeScreenshot(
  String description, {
  required Future<void> Function(WidgetTester tester) body,
}) {
  testGoldens(
    description,
    body,
    tags: const <String>['golden', 'readme-screenshot'],
  );
}
