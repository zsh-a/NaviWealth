import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );
}

/// The entrance opacity of [label]'s row, or `null` when the row renders
/// statically (no [AppEntrance] wrapper active).
double? _rowOpacity(WidgetTester tester, String label) {
  final opacity = find.ancestor(
    of: find.text(label),
    matching: find.byType(Opacity),
  );
  if (opacity.evaluate().isEmpty) return null;
  return tester.widget<Opacity>(opacity.first).opacity;
}

void main() {
  testWidgets('items animate on first reveal and settle at rest', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppEntranceScope(
          child: ListView.builder(
            itemCount: 50,
            itemExtent: 100,
            itemBuilder: (context, i) =>
                AppOnceEntrance(index: i, child: Text('item $i')),
          ),
        ),
      ),
    );

    expect(_rowOpacity(tester, 'item 0'), 0);

    await tester.pump(const Duration(milliseconds: 110));
    final mid = _rowOpacity(tester, 'item 0');
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));

    await tester.pump(const Duration(milliseconds: 200));
    expect(_rowOpacity(tester, 'item 0'), 1);
  });

  testWidgets('recycled rows do not replay the entrance on scroll back', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AppEntranceScope(
          child: ListView.builder(
            itemCount: 50,
            itemExtent: 100,
            itemBuilder: (context, i) =>
                AppOnceEntrance(index: i, child: Text('item $i')),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Scroll far down: rows revealed for the first time animate once.
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pump();
    expect(find.text('item 0'), findsNothing);
    final animating = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .where((opacity) => opacity.opacity < 1)
        .length;
    expect(animating, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 300));

    // Scroll back to the top: rows at or below the watermark render
    // statically — no entrance replay.
    await tester.drag(find.byType(ListView), const Offset(0, 1500));
    await tester.pump();
    expect(find.text('item 0'), findsOneWidget);
    expect(_rowOpacity(tester, 'item 0'), isNull);
  });

  testWidgets('rows appended beyond the watermark still animate once', (
    tester,
  ) async {
    Widget list(int count) => _wrap(
      AppEntranceScope(
        child: ListView(
          children: [
            for (var i = 0; i < count; i++)
              AppOnceEntrance(index: i, child: Text('item $i')),
          ],
        ),
      ),
    );

    await tester.pumpWidget(list(3));
    await tester.pump(const Duration(milliseconds: 300));

    // Same tree shape keeps the scope's State (and its watermark) alive:
    // previously revealed rows stay settled, only the new row animates.
    await tester.pumpWidget(list(4));
    expect(_rowOpacity(tester, 'item 1'), 1);
    expect(_rowOpacity(tester, 'item 3'), 0);

    await tester.pump(const Duration(milliseconds: 300));
    expect(_rowOpacity(tester, 'item 3'), 1);
  });

  testWidgets('reduce-motion users get no entrance', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AppEntranceScope(
          child: ListView.builder(
            itemCount: 50,
            itemExtent: 100,
            itemBuilder: (context, i) =>
                AppOnceEntrance(index: i, child: Text('item $i')),
          ),
        ),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    // Decorative role collapses to zero duration: the row is already at rest.
    expect(_rowOpacity(tester, 'item 0'), 1);
  });
}
