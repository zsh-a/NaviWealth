import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  group('GlassAppBar', () {
    testWidgets('renders the title and toolbar height matches AppBar', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            appBar: GlassAppBar(title: Text('Hello')),
            body: SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello'), findsOneWidget);
      // PreferredSize sums kToolbarHeight + bottom; with no bottom we
      // expect the bare toolbar height.
      final glass = tester.widget<GlassAppBar>(find.byType(GlassAppBar));
      expect(glass.preferredSize.height, kToolbarHeight);
    });

    testWidgets('preferredSize includes bottom widget height', (tester) async {
      const tabHeight = 48.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            appBar: GlassAppBar(
              title: Text('Tabs'),
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(tabHeight),
                child: SizedBox(height: tabHeight),
              ),
            ),
          ),
        ),
      );
      final glass = tester.widget<GlassAppBar>(find.byType(GlassAppBar));
      expect(glass.preferredSize.height, kToolbarHeight + tabHeight);
    });

    testWidgets(
      'wraps the inner AppBar in a transparent surface so the glass '
      'tint is what shows through',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(appBar: GlassAppBar(title: Text('x'))),
          ),
        );
        await tester.pumpAndSettle();
        final inner = tester.widget<AppBar>(find.byType(AppBar));
        expect(inner.backgroundColor, Colors.transparent);
        expect(inner.surfaceTintColor, Colors.transparent);
        expect(inner.elevation, 0);
        expect(inner.scrolledUnderElevation, 0);
      },
    );
  });

  group('GlassNavigationBar', () {
    testWidgets('forwards selection to NavigationBar callback', (tester) async {
      int? lastSelected;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: GlassNavigationBar(
              selectedIndex: 0,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'a'),
                NavigationDestination(icon: Icon(Icons.search), label: 'b'),
              ],
              onDestinationSelected: (i) => lastSelected = i,
            ),
          ),
        ),
      );
      await tester.tap(find.text('b'));
      await tester.pumpAndSettle();
      expect(lastSelected, 1);
    });

    testWidgets('inner NavigationBar is transparent so glass shows', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: GlassNavigationBar(
              selectedIndex: 0,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'a'),
                NavigationDestination(icon: Icon(Icons.search), label: 'b'),
              ],
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.backgroundColor, Colors.transparent);
      expect(bar.surfaceTintColor, Colors.transparent);
      expect(bar.elevation, 0);
    });
  });

  group('showGlassModalBottomSheet', () {
    testWidgets('returns the value provided by the sheet on Navigator.pop', (
      tester,
    ) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );

      final future = showGlassModalBottomSheet<String>(
        context: capturedContext,
        builder: (ctx) => SafeArea(
          child: TextButton(
            onPressed: () => Navigator.of(ctx).pop('answer'),
            child: const Text('go'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(await future, 'answer');
    });
  });

  group('Card theme', () {
    testWidgets('dark cards have a hairline border and no shadow', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: Card(child: SizedBox(width: 50, height: 50))),
        ),
      );
      await tester.pumpAndSettle();
      final cardTheme = Theme.of(
        tester.element(find.byType(Card)),
      ).cardTheme;
      expect(cardTheme.elevation, 0);
      final shape = cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.side.width, 1);
      // Hairline alpha matches GlassTokens hairline.
      expect(shape.side.color.a, closeTo(0.06, 0.02));
    });
  });
}
