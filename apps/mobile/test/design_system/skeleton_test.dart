import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(
  Widget child, {
  bool disableAnimations = false,
  Brightness brightness = Brightness.light,
}) {
  final fTheme = brightness == Brightness.dark
      ? FThemes.slate.dark.desktop
      : FThemes.slate.light.desktop;
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: FTheme(
        data: fTheme,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('SkeletonBox respects width / height', (tester) async {
    await tester.pumpWidget(
      _wrap(const SkeletonBox(width: 80, height: 24, shimmer: false)),
    );
    final size = tester.getSize(find.byType(SkeletonBox));
    expect(size.width, 80);
    expect(size.height, 24);
  });

  testWidgets('SkeletonBox runs the shimmer animation when motion is enabled', (
    tester,
  ) async {
    const key = ValueKey('shimmer');
    await tester.pumpWidget(
      _wrap(const SkeletonBox(key: key, width: 100, height: 16)),
    );
    // The animation drives a CustomPaint inside an AnimatedBuilder
    // descendant of our SkeletonBox.
    expect(
      find.descendant(of: find.byKey(key), matching: find.byType(CustomPaint)),
      findsWidgets,
    );
    // Tear the widget down so the running ticker doesn't leak past
    // the test boundary.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'SkeletonBox renders static block when MediaQuery disables animations',
    (tester) async {
      const key = ValueKey('reduce-motion');
      await tester.pumpWidget(
        _wrap(
          const SkeletonBox(key: key, width: 100, height: 16),
          disableAnimations: true,
        ),
      );
      // No animated CustomPaint inside the box — just the ColoredBox
      // fallback.
      expect(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: find.byKey(key), matching: find.byType(ColoredBox)),
        findsOneWidget,
      );
    },
  );

  testWidgets('SkeletonBox renders static block when shimmer flag is false', (
    tester,
  ) async {
    const key = ValueKey('shimmer-off');
    await tester.pumpWidget(
      _wrap(
        const SkeletonBox(key: key, width: 100, height: 16, shimmer: false),
      ),
    );
    expect(
      find.descendant(of: find.byKey(key), matching: find.byType(CustomPaint)),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byKey(key), matching: find.byType(ColoredBox)),
      findsOneWidget,
    );
  });

  testWidgets('SkeletonBox is excluded from semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _wrap(const SkeletonBox(shimmer: false, width: 40, height: 16)),
    );
    expect(find.bySemanticsLabel('Loading'), findsNothing);
    handle.dispose();
  });

  testWidgets('SkeletonCard wraps child in an FCard with padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SkeletonCard(
          child: SkeletonBox(width: 100, height: 16, shimmer: false),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(SkeletonCard),
        matching: find.byType(FCard),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SkeletonCard),
        matching: find.byType(SkeletonBox),
      ),
      findsOneWidget,
    );
  });

  testWidgets('AppListPageSkeleton mirrors one grouped list surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 420,
          height: 700,
          child: AppListPageSkeleton(itemCount: 3),
        ),
        disableAnimations: true,
      ),
    );

    expect(find.byType(AppGroupedSurface), findsOneWidget);
    expect(find.byType(AppGroupedDivider), findsNWidgets(2));
    expect(find.byType(SkeletonBox), findsNWidgets(13));
  });

  testWidgets('SkeletonBox dark-mode tones come from the active ColorScheme', (
    tester,
  ) async {
    const key = ValueKey('dark');
    await tester.pumpWidget(
      _wrap(
        const SkeletonBox(key: key, width: 50, height: 16, shimmer: false),
        brightness: Brightness.dark,
      ),
    );
    final colored = tester.widget<ColoredBox>(
      find
          .descendant(of: find.byKey(key), matching: find.byType(ColoredBox))
          .first,
    );
    final ctx = tester.element(find.byKey(key));
    expect(colored.color, ctx.theme.colors.muted);
  });
}
