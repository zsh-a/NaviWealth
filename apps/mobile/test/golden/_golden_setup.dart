import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

/// FIR-113 visual baseline harness.
///
/// All page goldens go through [pumpGoldenPage] so the device profile,
/// font fallback, theme, and surface size are identical across the suite.
/// Adding a new page golden should not require re-deriving any of this.

/// Logical mobile profile used for every golden in this directory:
/// iPhone 14 Pro size at 2x dpr, no text scaling. The width is just under
/// the [Breakpoints.mobile] cutoff so pages render their single-column
/// (mobile) layout — desktop two-column / master-detail variants are
/// out of scope per FIR-113.
const Size kGoldenLogicalSize = Size(390, 844);
const double kGoldenDpr = 2.0;

enum GoldenTheme { dark, colorblind }

extension GoldenThemeData on GoldenTheme {
  String get filenameSuffix {
    switch (this) {
      case GoldenTheme.dark:
        return 'dark';
      case GoldenTheme.colorblind:
        return 'colorblind';
    }
  }

  ThemeData buildTheme() {
    switch (this) {
      case GoldenTheme.dark:
        return AppTheme.dark();
      case GoldenTheme.colorblind:
        return AppTheme.dark();
    }
  }

  MarketColors get marketColors {
    switch (this) {
      case GoldenTheme.dark:
        return MarketColors.fromMode(
          MarketColorMode.redUpGreenDown,
          brightness: Brightness.dark,
        );
      case GoldenTheme.colorblind:
        return MarketColors.fromMode(
          MarketColorMode.colorblind,
          brightness: Brightness.dark,
        );
    }
  }
}

bool _fontsLoaded = false;

const List<String> _goldenFontAssets = <String>[
  'assets/fonts/inter-regular.woff2',
  'assets/fonts/inter-medium.woff2',
  'assets/fonts/inter-semibold.woff2',
  'assets/fonts/inter-bold.woff2',
  'assets/fonts/outfit-bold.woff2',
  'assets/fonts/app-cn-base.woff2',
  'assets/fonts/app-cn-ext.woff2',
];

void _verifyGoldenFontAssets() {
  final missingOrEmpty = <String>[];
  for (final path in _goldenFontAssets) {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) {
      missingOrEmpty.add(path);
    }
  }
  if (missingOrEmpty.isEmpty) return;

  throw StateError(
    'Golden font assets are missing or empty:\n'
    '${missingOrEmpty.map((path) => '  - $path').join('\n')}\n'
    'Run apps/mobile/tool/build-latin-fonts.sh and '
    'apps/mobile/tool/build-cn-fonts.sh before golden tests.',
  );
}

/// Load every font declared in `pubspec.yaml` (Inter, Outfit, AppCnSans).
///
/// On CI these .woff2 files are regenerated before the golden job starts. The
/// assets are gitignored build artifacts, so fail early if a checkout only has
/// empty placeholder files; otherwise Flutter can silently fall back to its
/// built-in test font and make the PNG baseline meaningless.
Future<void> loadGoldenFonts() async {
  if (_fontsLoaded) return;
  _verifyGoldenFontAssets();
  await loadAppFonts();
  _fontsLoaded = true;
}

/// Pump a single mobile-size golden of [child] under [variant] and write
/// the snapshot to `goldens/<name>_<variant>.png` next to the test file.
///
/// [overrides] are forwarded to the wrapping [ProviderScope] so each page
/// stubs its own data providers without leaking dependencies into the
/// shared harness.
///
/// Wrap the call in [testGoldens] from `golden_toolkit` and add the
/// `'golden'` tag so `flutter test --tags=golden` picks it up. See any of
/// the page tests in this directory for the canonical pattern.
Future<void> pumpAndSnapshotMobile(
  WidgetTester tester, {
  required String name,
  required GoldenTheme variant,
  required Widget child,
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
}) async {
  await loadGoldenFonts();
  await tester.binding.setSurfaceSize(kGoldenLogicalSize);
  tester.view.physicalSize = Size(
    kGoldenLogicalSize.width * kGoldenDpr,
    kGoldenLogicalSize.height * kGoldenDpr,
  );
  tester.view.devicePixelRatio = kGoldenDpr;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  // Wrap every page in a GoRouter so calls like `selectedQueryOf(context)`
  // and `context.push(...)` resolve. The router serves [child] at `/` and
  // declares the path-only `/_unused/...` catch-all so any context.push
  // target invoked from the page (FAB onPressed, etc.) doesn't fail at
  // build time — pushes into nowhere are silently absorbed at the lookup,
  // since the test never actually triggers them.
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => child)],
    errorBuilder: (_, _) => const SizedBox.shrink(),
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    // `disableAnimations: true` quiets the SkeletonBox shimmer
    // AnimationController (it gates on MediaQuery.disableAnimationsOf in
    // _syncAnimation) and stops fl_chart entry tweens. Without it the
    // ticker stays live past the test body and the framework asserts
    // "A Timer is still pending after the widget tree was disposed."
    // Goldens want a still frame, not a partial paint of a moving band,
    // so disabling motion is the right call regardless of the timer fix.
    MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: ProviderScope(
        overrides: overrides,
        child: MarketColorsScope(
          colors: variant.marketColors,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: variant.buildTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            routerConfig: router,
          ),
        ),
      ),
    ),
  );
  // Advance a fixed number of frames so async provider completions and first
  // paints land deterministically. Avoid pumpAndSettle here: several golden
  // surfaces intentionally keep a ticker alive, and timeout fallbacks can
  // capture different frames on different hosts.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));

  await expectGoldenSurface('goldens/${name}_${variant.filenameSuffix}.png');
}

/// Compare the whole app surface against [goldenPath] without
/// GoldenToolkit's implicit pumpAndSettle.
///
/// The directory-local flutter_test_config skips PNG assertion off Linux.
/// This helper mirrors that policy because it intentionally bypasses
/// GoldenToolkit's [screenMatchesGolden] to avoid settling on intentionally
/// live tickers.
Future<void> expectGoldenSurface(String goldenPath) async {
  if (!Platform.isLinux && !autoUpdateGoldenFiles) return;

  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

/// Convenience: declare a `testGoldens` block that captures a page in every
/// theme variant. The closure receives the variant so callers can pass it to
/// [pumpAndSnapshotMobile].
void runAllVariants(
  String pageName,
  Future<void> Function(WidgetTester tester, GoldenTheme variant) body,
) {
  for (final variant in GoldenTheme.values) {
    testGoldens(
      '$pageName — ${variant.filenameSuffix}',
      (tester) => body(tester, variant),
      tags: 'golden',
    );
  }
}

enum ResponsiveGoldenProfile { narrow, wide, textScale }

extension ResponsiveGoldenProfileData on ResponsiveGoldenProfile {
  Size get logicalSize => switch (this) {
    ResponsiveGoldenProfile.narrow ||
    ResponsiveGoldenProfile.textScale => const Size(390, 844),
    ResponsiveGoldenProfile.wide => const Size(1280, 900),
  };

  double get devicePixelRatio => switch (this) {
    ResponsiveGoldenProfile.narrow || ResponsiveGoldenProfile.textScale => 2,
    ResponsiveGoldenProfile.wide => 1,
  };

  TextScaler get textScaler => switch (this) {
    ResponsiveGoldenProfile.textScale => const TextScaler.linear(2),
    _ => TextScaler.noScaling,
  };

  TargetPlatform get targetPlatform => switch (this) {
    ResponsiveGoldenProfile.narrow ||
    ResponsiveGoldenProfile.textScale => TargetPlatform.iOS,
    ResponsiveGoldenProfile.wide => TargetPlatform.linux,
  };

  bool get touch => switch (this) {
    ResponsiveGoldenProfile.narrow || ResponsiveGoldenProfile.textScale => true,
    ResponsiveGoldenProfile.wide => false,
  };

  bool get compact => switch (this) {
    ResponsiveGoldenProfile.narrow ||
    ResponsiveGoldenProfile.textScale => false,
    ResponsiveGoldenProfile.wide => true,
  };
}

const _responsiveGoldenMediaKey = ValueKey('responsive-golden.media-query');

/// New dark-only responsive golden path. The legacy mobile/theme helpers above
/// intentionally remain independent so their 48 baselines cannot drift.
Future<void> pumpAndSnapshotResponsive(
  WidgetTester tester, {
  required String name,
  required ResponsiveGoldenProfile profile,
  required Widget child,
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
}) async {
  final previousPlatformOverride = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = profile.targetPlatform;
  addTearDown(() {
    debugDefaultTargetPlatformOverride = previousPlatformOverride;
  });

  try {
    final materialTheme = AppTheme.dark(compact: profile.compact);
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
      routes: [GoRoute(path: '/', builder: (_, _) => child)],
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
            theme: materialTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: locale,
            routerConfig: router,
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  disableAnimations: true,
                  textScaler: profile.textScaler,
                ),
                child: FTheme(
                  data: buildAppForuiTheme(
                    brightness: Brightness.dark,
                    touch: profile.touch,
                  ),
                  child: Builder(
                    key: _responsiveGoldenMediaKey,
                    builder: (_) => child!,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    final expectedPhysical = profile == ResponsiveGoldenProfile.wide
        ? const Size(1280, 900)
        : const Size(780, 1688);
    expect(tester.view.physicalSize, expectedPhysical);
    final mediaContext = tester.element(find.byKey(_responsiveGoldenMediaKey));
    expect(MediaQuery.sizeOf(mediaContext), logicalSize);
    expect(
      MediaQuery.textScalerOf(mediaContext).scale(10),
      profile == ResponsiveGoldenProfile.textScale ? 20 : 10,
    );
    final foruiTheme = FTheme.of(mediaContext);
    expect(
      foruiTheme.buttonStyles.primary.md.contentStyle.constraints.minHeight,
      profile.touch ? 44 : 36,
    );
    expect(foruiTheme.colors.primary, AccentColors.primary(Brightness.dark));
    final materialThemeAtProfile = Theme.of(mediaContext);
    expect(materialThemeAtProfile.platform, profile.targetPlatform);
    expect(
      materialThemeAtProfile.visualDensity,
      profile.compact ? VisualDensity.compact : VisualDensity.standard,
    );
    expect(tester.takeException(), isNull);
    await expectGoldenSurface('goldens/$name.png');
  } finally {
    debugDefaultTargetPlatformOverride = previousPlatformOverride;
  }
}

void runResponsiveGolden(
  String description, {
  required ResponsiveGoldenProfile profile,
  required Future<void> Function(
    WidgetTester tester,
    ResponsiveGoldenProfile profile,
  )
  body,
}) {
  testGoldens(
    description,
    (tester) => body(tester, profile),
    tags: const ['golden', 'responsive-golden'],
  );
}
